# Copyright (c) 2024 Bytedance Ltd. and/or its affiliates

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import csv
import json
import random
import re
import requests
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, List, Dict, Any

from multi_swe_bench.collect.util import get_tokens, make_request_with_retry
from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient

# GitHub API配置
GITHUB_API_BASE = "https://api.github.com"
HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}


def extract_related_issues(pr_title: str, pr_body: str) -> Optional[List[int]]:
    issue_pattern = re.compile(r"#(\d+)")
    issue_refs = set()

    for text in [pr_body, pr_title]:
        for match in issue_pattern.finditer(text):
            issue_refs.add(int(match.group(1)))

    return list(issue_refs) if issue_refs else None


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="A command-line tool for processing repositories."
    )
    parser.add_argument(
        "--input", type=Path, required=True, help="Input CSV file with repositories."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("."),
        help="Output directory for filtered PRs files.",
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


def extract_resolved_issues(pull: dict) -> list[int]:
    """
    Extract resolved issues from PR data.
    """
    issue_keywords = {
        "close",
        "closes",
        "closed",
        "fix",
        "fixes",
        "fixed",
        "resolve",
        "resolves",
        "resolved",
    }

    extra_refactor_keywords = {"refactor", "ref", "internal refactoring"}
    all_keywords = issue_keywords.union(extra_refactor_keywords)

    issues_pat = re.compile(r"(\w+)\s*\#(\d+)")

    title = pull.get("title") or ""
    body = pull.get("body") or ""
    commits = pull.get("commits", [])
    commits_msgs = [
        commit.get("message") or "" for commit in commits if isinstance(commit, dict)
    ]
    text = title + "\n" + body
    text += "\n" + "\n".join(commits_msgs)

    text = re.sub(r"(?s)<!--.*?-->", "", text)

    references = dict(issues_pat.findall(text))
    resolved_issues = set()
    for word, issue_num in references.items():
        if word.lower() in issue_keywords:
            resolved_issues.add(int(issue_num))

    if not resolved_issues:
        for kw in extra_refactor_keywords:
            if kw.lower() in text.lower():
                found_numbers = re.findall(r"#(\d+)", text)
                if found_numbers:
                    for num_str in found_numbers:
                        resolved_issues.add(int(num_str))

                if not resolved_issues:
                    issue_url = pull.get("issue_url") or ""
                    if issue_url:
                        issue_num = issue_url.split("/")[-1]
                        if issue_num.isdigit():
                            resolved_issues.add(int(issue_num))

                if not resolved_issues:
                    resolved_issues.add(-1)
                break

    return list(resolved_issues)


def fetch_commits_from_graphql(
    client: GitHubGraphQLClient,
    org: str,
    repo: str,
    pr_number: int,
) -> List[Dict[str, Any]]:
    """
    Fetch commits for a PR using GraphQL API.
    """
    query = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          commits(first: 100) {
            nodes {
              oid
              message
              parents(first: 10) {
                nodes {
                  oid
                }
              }
            }
          }
        }
      }
    }
    """

    variables = {
        "owner": org,
        "name": repo,
        "number": pr_number,
    }

    try:
        result = client.execute_query(query, variables)
        if "errors" in result:
            print(f"GraphQL errors fetching commits: {result['errors']}")
            return []

        repo_data = result.get("repository", {})
        pr_data = repo_data.get("pullRequest", {})
        commits_data = pr_data.get("commits", {})
        nodes = commits_data.get("nodes", [])

        commits = []
        for node in nodes:
            parents_data = node.get("parents", {}).get("nodes", [])
            parents = [p.get("oid") for p in parents_data]
            commits.append(
                {
                    "sha": node.get("oid"),
                    "message": node.get("message", ""),
                    "parents": parents,
                }
            )

        return commits

    except Exception as e:
        print(f"Error fetching commits for PR #{pr_number}: {e}")
        return []


def search_prs_with_graphql(
    client: GitHubGraphQLClient,
    org: str,
    repo: str,
    token: str,
    merged_after: Optional[str] = None,
    merged_before: Optional[str] = None,
    key_words: Optional[str] = None,
    max_results: int = 1000,
) -> List[Dict[str, Any]]:
    """
    Search for merged PRs in a repository using GitHub GraphQL API.
    """
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
                    message
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
                    target {
                      ... on Commit {
                        oid
                      }
                    }
                  }
                  headRef {
                    name
                    target {
                      ... on Commit {
                        oid
                      }
                    }
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
            print(f"GraphQL result: {result}")
            if "errors" in result:
                print(f"GraphQL errors: {result['errors']}")
                break
            search_result = result.get("search", {})
            edges = search_result.get("edges", [])
            page_info = search_result.get("pageInfo", {})

            for edge in edges:
                node = edge.get("node", {})
                if node:
                    merge_commit = node.get("mergeCommit", {}) or {}
                    base_ref = node.get("baseRef", {}) or {}
                    head_ref = node.get("headRef", {}) or {}

                    pr_number = node.get("number")
                    repo_full_name = f"{org}/{repo}"
                    api_base = f"https://api.github.com/repos/{repo_full_name}"

                    # Extract related issue numbers from PR content
                    pr_body = node.get("body", "")
                    pr_title = node.get("title", "")

                    issue_pattern = re.compile(r"#(\d+)")
                    issue_refs = set()

                    for text in [pr_body, pr_title]:
                        for match in issue_pattern.finditer(text):
                            issue_refs.add(int(match.group(1)))

                    issue_refs = list(issue_refs) if issue_refs else None

                    pr_data = {
                        "org": org,
                        "repo": repo,
                        "number": pr_number,
                        "state": node.get("state"),
                        "title": node.get("title", ""),
                        "body": node.get("body", ""),
                        "url": node.get("url"),
                        "id": node.get("id"),
                        "html_url": node.get("url"),
                        "diff_url": f"{node.get('url')}.diff",
                        "patch_url": f"{node.get('url')}.patch",
                        "issue_url": node.get("url"),
                        "created_at": node.get("createdAt"),
                        "updated_at": node.get("updatedAt"),
                        "closed_at": node.get("closedAt"),
                        "merged_at": node.get("mergedAt"),
                        "merge_commit_sha": merge_commit.get("oid"),
                        "commits": [
                            {
                                "oid": merge_commit.get("oid", ""),
                                "message": merge_commit.get("message", ""),
                            }
                        ],
                        # "base_commit_hash": base_ref.get("target", {}).get("oid")
                        # if base_ref.get("target")
                        # else None,
                        "base_commit_hash": head_ref.get("target", {}).get("oid")
                        if head_ref.get("target")
                        else None,
                        "head_ref_name": head_ref.get("name") if head_ref else None,
                        "related_issues": issue_refs,
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
                        f"Found PR: {pr_data['number']}, state: {pr_data['state']}, merged_at: {pr_data['merged_at']}, issues: {issue_refs}"
                    )
                    if pr_data["base_commit_hash"] is None:
                        ## call
                        pr_data["base_commit_hash"] = get_correct_commit_hash(
                            repo_full_name, pr_number, token
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


def get_correct_commit_hash(repo_path, pr_number, token):
    """
    通过GitHub API获取PR的正确commit hash
    """
    url = f"{GITHUB_API_BASE}/repos/{repo_path}/pulls/{pr_number}"

    headers = HEADERS.copy()
    if token:
        headers["Authorization"] = f"Bearer {token}"

    response = requests.get(url, headers=headers)

    # 处理速率限制
    if response.status_code == 429:
        reset_time = int(response.headers.get("X-RateLimit-Reset", time.time() + 60))
        sleep_time = max(reset_time - int(time.time()), 0) + 1
        print(f"Rate limited. Sleeping for {sleep_time} seconds...")
        time.sleep(sleep_time)
        return get_correct_commit_hash(repo_path, pr_number, token)  # 重试

    # 处理其他HTTP错误
    response.raise_for_status()

    data = response.json()
    return data["head"]["sha"]


def is_relevant_pull(pull, key_words: Optional[str] = None) -> bool:
    """
    Filter PRs by keywords.
    """
    title = pull.get("title", "").lower()
    labels = [label.get("name", "").lower() for label in pull.get("labels", [])]
    body = pull.get("body", "").lower()

    default_keywords = {""}

    if key_words is not None and key_words != "":
        user_keywords = {w.strip().lower() for w in key_words.split(",")}
        keywords = user_keywords
    else:
        keywords = default_keywords

    if any(k in label for label in labels for k in keywords):
        return True
    if any(k in title for k in keywords):
        return True
    if any(k in body for k in keywords):
        return True

    return False


def main(
    tokens: list[str],
    input_csv: Path,
    output_dir: Path = Path("."),
    key_words: Optional[str] = None,
    merged_after: Optional[str] = None,
    merged_before: Optional[str] = None,
):
    print("starting get all pull requests using GraphQL")
    print(f"Input CSV: {input_csv}")
    print(f"Tokens: {tokens}")
    print(f"Merged After: {merged_after}")
    print(f"Merged Before: {merged_before}")
    print(f"Key Words: {key_words}")

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

    # if tokens:
    tk = random.choice(tokens)
    print("Using token:", tk)
    client = GitHubGraphQLClient(tk)
    # else:
    #     print("No tokens available. Cannot use GraphQL API.")
    #     return

    total_prs = 0
    for org, repo in repositories:
        print(f"Processing repository: {org}/{repo}")

        prs = search_prs_with_graphql(
            client,
            org,
            repo,
            tk,
            merged_after,
            merged_before,
            key_words,
            max_results=1000,
        )

        if not prs:
            print(f"No PRs found for {org}/{repo}")
            continue

        output_filename = output_dir / f"{org}__{repo}_filtered_prs.jsonl"

        fetched = 0
        with open(output_filename, "w", encoding="utf-8") as file:
            for pr_data in prs:
                pr_number = pr_data["number"]

                if key_words is not None and key_words != "":
                    if not is_relevant_pull(pr_data, key_words):
                        print(f"Skipping PR #{pr_number} not matching keywords")
                        continue

                print(f"Processing PR #{pr_number}")

                # commits_data = fetch_commits_from_graphql(client, org, repo, pr_number)
                # resolved_issues = extract_resolved_issues(
                #     {
                #         "title": pr_data.get("title", ""),
                #         "body": pr_data.get("body", ""),
                #         # "commits": commits_data,
                #     }
                # )
                related_issues = extract_related_issues(
                    pr_data["title"], pr_data["body"]
                )

                # pr_data["commits"] = commits_data
                pr_data["resolved_issues"] = related_issues

                file.write(
                    json.dumps(
                        pr_data,
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                fetched += 1
                total_prs += 1

        print(f"Fetched {fetched} merged PRs from {org}/{repo} -> {output_filename}")

    print(f"Total PRs fetched across all repositories: {total_prs}")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)

    main(
        tokens,
        args.input,
        args.output_dir,
        args.key_words,
        args.merged_after,
        args.merged_before,
    )
