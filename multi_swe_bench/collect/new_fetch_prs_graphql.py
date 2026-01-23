# Copyright (c) 2024 Bytedance Ltd. and/or its affiliates

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

import argparse
import json
import random
import re
import requests
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, List, Dict, Any

from multi_swe_bench.collect.util import get_tokens, make_request_with_retry
from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="A command-line tool for processing repositories."
    )
    parser.add_argument(
        "--input", type=Path, required=True, help="Input CSV file with repositories."
    )
    parser.add_argument(
        "--output", type=Path, required=True, help="Output JSONL file for PRs."
    )
    parser.add_argument(
        "--tokens",
        type=str,
        nargs="*",
        default=None,
        help="API token(s) or path to token file.",
    )

    parser.add_argument(
        "--merged-after",
        type=str,
        required=False,
        default=None,
        help="Filter PRs merged after this datetime (ISO format).",
    )
    parser.add_argument(
        "--merged-before",
        type=str,
        required=False,
        default=None,
        help="Filter PRs merged before this datetime (ISO format).",
    )
    parser.add_argument(
        "--key_words",
        type=str,
        required=False,
        default=None,
        help="keywords to filter PRs, separated by commas.",
    )
    return parser


# def get_github(token) -> Github:
#     auth = Auth.Token(token)
#     return Github(auth=auth, per_page=100)


def search_prs_with_graphql(
    client: GitHubGraphQLClient,
    org: str,
    repo: str,
    merged_after: Optional[str] = None,
    merged_before: Optional[str] = None,
    key_words: Optional[str] = None,
    max_results: int = 1000,
) -> List[Dict[str, Any]]:
    """
    Search for merged PRs in a repository using GitHub GraphQL API.
    """
    # Build search query
    query_parts = [f"repo:{org}/{repo}", "is:pr", "is:merged"]

    if merged_after:
        query_parts.append(f"merged:>={merged_after}")
    if merged_before:
        query_parts.append(f"merged:<={merged_before}")
    if key_words:
        for kw in key_words.split(","):
            kw_clean = kw.strip()
            if kw_clean:
                query_parts.append(f'"{kw_clean}"')

    search_query = " ".join(query_parts)
    print(f"GraphQL search query: {search_query}")
    print(
        f"Debug: org={org}, repo={repo}, merged_after={merged_after}, merged_before={merged_before}"
    )

    # GraphQL query for PR search with full details
    query = """
    query($query: String!, $first: Int!, $after: String) {
      search(query: $query, type: ISSUE, first: $first, after: $after) {
        edges {
          node {
            ... on PullRequest {
              number
              title
              body
              createdAt
              updatedAt
              closedAt
              mergedAt
              mergeCommit {
                oid
              }
              url
              id
              state
              isDraft
              labels(first: 10) {
                nodes {
                  name
                }
              }
              baseRef {
                name
              }
              headRef {
                name
              }
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    """

    prs = []
    cursor = None
    page_size = 100

    while len(prs) < max_results:
        variables = {
            "query": search_query,
            "first": min(page_size, max_results - len(prs)),
            "after": cursor,
        }

        try:
            result = client.execute_query(query, variables)
            print(f"GraphQL result: {result}")  # Debug output
            if "errors" in result:
                print(f"GraphQL errors: {result['errors']}")
                break
            search_result = result.get("search", {})
            edges = search_result.get("edges", [])
            page_info = search_result.get("pageInfo", {})

            for edge in edges:
                node = edge.get("node", {})
                if node:
                    # Extract all PR data from GraphQL response
                    merge_commit = node.get("mergeCommit", {}) or {}
                    base_ref = node.get("baseRef", {}) or {}

                    # Construct REST API URLs from available data
                    pr_number = node.get("number")
                    repo_full_name = f"{org}/{repo}"
                    api_base = f"https://api.github.com/repos/{repo_full_name}"

                    pr_data = {
                        "number": pr_number,
                        "state": node.get("state"),
                        "title": node.get("title", ""),
                        "body": node.get("body", ""),
                        "url": node.get("url"),
                        "id": node.get("id"),
                        "html_url": node.get(
                            "url"
                        ),  # GraphQL url is the same as html_url
                        "diff_url": f"{node.get('url')}.diff",
                        "patch_url": f"{node.get('url')}.patch",
                        "issue_url": node.get("url"),  # Same as url for PRs
                        "created_at": node.get("createdAt"),
                        "updated_at": node.get("updatedAt"),
                        "closed_at": node.get("closedAt"),
                        "merged_at": node.get("mergedAt"),
                        "merge_commit_sha": merge_commit.get("oid"),
                        "labels": [
                            {"name": label.get("name", "")}
                            for label in node.get("labels", {}).get("nodes", [])
                        ],
                        "draft": node.get("isDraft", False),
                        "commits_url": f"{api_base}/pulls/{pr_number}/commits",
                        "review_comments_url": f"{api_base}/pulls/{pr_number}/comments",
                        "review_comment_url": f"{api_base}/pulls/{pr_number}/comments",
                        "comments_url": f"{api_base}/issues/{pr_number}/comments",
                        "base": {
                            "ref": base_ref.get("name", ""),
                            "repo": {"name": repo, "full_name": repo_full_name},
                        }
                        if base_ref
                        else None,
                    }
                    print(
                        f"Found PR: {pr_data['number']}, state: {pr_data['state']}, merged_at: {pr_data['merged_at']}"
                    )
                    prs.append(pr_data)

            if not page_info.get("hasNextPage", False):
                break

            cursor = page_info.get("endCursor")

        except Exception as e:
            print(f"Error in GraphQL search: {e}")
            break

    print(f"Total PRs found in GraphQL search: {len(prs)}")
    return prs[:max_results]


def is_relevant_pull(pull, key_words: Optional[str] = None) -> bool:
    """
    判断 PR 是否可能是修复 issue 的 PR。
    """

    title = pull.title.lower() if pull.title else ""
    labels = [label.name.lower() for label in pull.labels]

    # rule 1: title: fix #123
    # if re.search(r"fix\s*#\d+", title, re.IGNORECASE):
    #     return True

    # 默认关键词
    default_keywords = {""}

    # 用户指定 key_words（允许多个关键词用逗号分隔）
    if key_words is not None and key_words != "":
        user_keywords = {w.strip().lower() for w in key_words.split(",")}
        keywords = user_keywords
    else:
        keywords = default_keywords

    # print(f"=== Using keywords for filtering: {keywords}")
    # rule 2: labels contain keywords
    # if any(k in label for label in labels for k in keywords):
    #     return True
    if any(k in label for label in labels for k in keywords):
        return True
    if any(k in title for k in keywords):
        return True
    if pull.body and any(k in pull.body.lower() for k in keywords):
        return True

    return False


def main(
    tokens: list[str],
    input_csv: Path,
    output_jsonl: Path,
    key_words: Optional[str] = None,
    merged_after: Optional[str] = None,
    merged_before: Optional[str] = None,
):
    print("starting get all pull requests")
    print(f"Input CSV: {input_csv}")
    print(f"Output JSONL: {output_jsonl}")
    print(f"Tokens: {tokens}")
    print(f"Merged After: {merged_after}")
    print(f"Merged Before: {merged_before}")
    print(f"Key Words: {key_words}")

    # Read repositories from CSV
    import csv

    repositories = []
    with open(input_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            name = row.get("Name", "").strip()
            if name and "/" in name:
                org, repo = name.split("/", 1)
                repositories.append((org, repo))

    print(f"Found {len(repositories)} repositories to process")

    print("token:", tokens)
    if tokens:
        tk = random.choice(tokens)
        print("Using token:", tk)
        client = GitHubGraphQLClient(tk)
    else:
        print("No tokens available. Cannot use GraphQL API.")
        return

    def datetime_serializer(obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return obj

    total_prs = 0
    with open(output_jsonl, "w", encoding="utf-8") as file:
        for org, repo in repositories:
            print(f"Processing repository: {org}/{repo}")

            # Use GraphQL to search for PRs
            prs = search_prs_with_graphql(
                client,
                org,
                repo,
                merged_after,
                merged_before,
                key_words,
                max_results=1000,
            )

            fetched = 0
            for pr_data in prs:
                pr_number = pr_data["number"]

                # Additional keyword filtering if needed (GraphQL already filters, but double-check)
                if key_words is not None and key_words != "":
                    # Create a mock pull object for filtering
                    class MockLabel:
                        def __init__(self, name):
                            self.name = name

                    class MockPull:
                        def __init__(self, data):
                            self.title = data.get("title", "")
                            self.body = data.get("body", "")
                            self.labels = [
                                MockLabel(label.get("name", ""))
                                for label in data.get("labels", [])
                            ]

                    mock_pull = MockPull(pr_data)
                    if not is_relevant_pull(mock_pull, key_words):
                        print(f"Skipping PR #{pr_number} not matching keywords")
                        continue

                print(f"✅ Processing PR #{pr_number} merged at {pr_data['merged_at']}")

                # Write PR data directly from GraphQL results (no REST API call needed)
                file.write(
                    json.dumps(
                        pr_data,
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                fetched += 1
                total_prs += 1

            print(f"Fetched {fetched} merged PRs from {org}/{repo}")

    print(f"Total PRs fetched: {total_prs}")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)

    main(
        tokens,
        args.input,
        args.output,
        args.key_words,
        args.merged_after,
        args.merged_before,
    )
