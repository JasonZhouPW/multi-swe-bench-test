#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path
from typing import Optional, List, Dict, Any

from multi_swe_bench.collect.util import get_tokens
from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def extract_related_issues(pr_title: str, pr_body: str) -> Optional[List[int]]:
    issue_pattern = re.compile(r"#(\d+)")
    issue_refs = set()

    for text in [pr_body, pr_title]:
        for match in issue_pattern.finditer(text):
            issue_refs.add(int(match.group(1)))

    return list(issue_refs) if issue_refs else None


def fetch_prs_with_details(
    client: GitHubGraphQLClient,
    org: str,
    repo: str,
    max_results: int = 10,
    merged_after: Optional[str] = None,
) -> List[Dict[str, Any]]:
    prs = []
    cursor = None
    fetched = 0

    print(f"Fetching PRs from {org}/{repo}...")

    while fetched < max_results:
        query_parts = [f"repo:{org}/{repo}", "is:pr", "is:merged"]

        if merged_after:
            query_parts.append(f"merged:>={merged_after}")

        search_query = " ".join(query_parts)
        print(f"search_query:{search_query}\n")
        query = """
        query($query: String!, $first: Int!, $after: String) {
          search(query: $query, type: ISSUE, first: $first, after: $after) {
            edges {
              node {
                ... on PullRequest {
                  number
                  title
                  body
                  state
                  url
                  createdAt
                  updatedAt
                  mergedAt
                  closedAt
                  isDraft
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
                  }
                  mergeCommit {
                    oid
                    message
                  }
                  labels(first: 20) {
                    nodes {
                      name
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

        variables = {"query": search_query, "first": 50, "after": cursor}

        result = client.execute_query(query, variables)

        if "errors" in result:
            print(f"GraphQL errors: {result['errors']}")
            break

        search_result = result.get("search", {})
        edges = search_result.get("edges", [])
        page_info = search_result.get("pageInfo", {})

        for edge in edges:
            if fetched >= max_results:
                break

            node = edge.get("node", {})
            if not node:
                continue

            pr_number = node.get("number")
            pr_title = node.get("title", "")
            pr_body = node.get("body", "")

            base_ref = node.get("baseRef", {}) or {}
            base_commit_hash = (
                base_ref.get("target", {}).get("oid")
                if base_ref.get("target")
                else None
            )

            head_ref = node.get("headRef", {}) or {}
            head_ref_name = head_ref.get("name") if head_ref else None

            merge_commit = node.get("mergeCommit", {}) or {}
            merge_commit_sha = merge_commit.get("oid")

            related_issues = extract_related_issues(pr_title, pr_body)

            labels = [
                {"name": label.get("name", "")}
                for label in node.get("labels", {}).get("nodes", [])
            ]

            pr_details = {
                "org": org,
                "repo": repo,
                "number": pr_number,
                "title": pr_title,
                "state": node.get("state"),
                "base_commit_hash": base_commit_hash,
                "merge_commit_sha": merge_commit_sha,
                "head_ref_name": head_ref_name,
                "related_issues": related_issues,
                "labels": labels,
                "is_draft": node.get("isDraft", False),
                "created_at": node.get("createdAt"),
                "updated_at": node.get("updatedAt"),
                "merged_at": node.get("mergedAt"),
                "closed_at": node.get("closedAt"),
                "url": node.get("url"),
            }

            prs.append(pr_details)
            fetched += 1

            print(f"\n--- PR #{pr_number} ---")
            print(f"Title: {pr_title}")
            print(f"State: {node.get('state')}")
            print(f"Base Commit Hash: {base_commit_hash}")
            print(f"Merge Commit SHA: {merge_commit_sha}")
            print(f"Head Ref: {head_ref_name}")
            print(f"Related Issues: {related_issues}")
            print(f"Labels: {[label['name'] for label in labels]}")
            print(f"Merged At: {node.get('mergedAt')}")
            print(f"URL: {node.get('url')}")

        if not page_info.get("hasNextPage", False):
            break

        cursor = page_info.get("endCursor")

    return prs


def main():
    parser = argparse.ArgumentParser(
        description="Test script to extract PR details including base commit hash and related issues"
    )
    parser.add_argument(
        "--org", type=str, required=True, help="GitHub organization name"
    )
    parser.add_argument(
        "--repo", type=str, required=True, help="GitHub repository name"
    )
    parser.add_argument(
        "--max-results",
        type=int,
        default=10,
        help="Maximum number of PRs to fetch (default: 10)",
    )
    parser.add_argument(
        "--merged-after",
        type=str,
        help="Filter PRs merged after this date (format: YYYY-MM-DD, e.g., 2025-12-01)",
    )
    parser.add_argument(
        "--output", type=Path, help="Output file to save results (optional)"
    )
    parser.add_argument(
        "--tokens",
        type=Path,
        default=Path("./tokens.txt"),
        help="Path to GitHub tokens file (default: ./tokens.txt)",
    )

    args = parser.parse_args()

    # Initialize GitHub GraphQL client
    tokens = get_tokens(str(args.tokens))
    if not tokens:
        print("Error: No GitHub tokens found!")
        return 1

    client = GitHubGraphQLClient(tokens[0])

    try:
        # Fetch PRs with detailed information
        prs = fetch_prs_with_details(
            client=client,
            org=args.org,
            repo=args.repo,
            max_results=args.max_results,
            merged_after=args.merged_after,
        )

        print(f"\n=== Summary ===")
        print(f"Fetched {len(prs)} pull requests from {args.org}/{args.repo}")

        # Statistics
        prs_with_related_issues = sum(1 for pr in prs if pr.get("related_issues"))
        prs_with_base_commit = sum(1 for pr in prs if pr.get("base_commit_hash"))

        print(f"PRs with related issues: {prs_with_related_issues}/{len(prs)}")
        print(f"PRs with base commit hash: {prs_with_base_commit}/{len(prs)}")

        # Save results if output file specified
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(prs, f, indent=2, ensure_ascii=False)
            print(f"Results saved to {args.output}")

        return 0

    except Exception as e:
        print(f"Error: {e}")
        return 1


if __name__ == "__main__":
    exit(main())
