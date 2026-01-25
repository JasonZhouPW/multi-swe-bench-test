#!/usr/bin/env python3

import sys

sys.path.insert(0, "../")

from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def main():
    token = "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"
    client = GitHubGraphQLClient(token)

    org = "rust-lang"
    repo = "rust"
    pr_number = 151615

    # Test 1: Get commits for a PR (check mergeCommit and baseRef structure)
    query1 = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          commits(first: 5) {
            nodes {
              oid
              message
              parents(first: 2) {
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

    print("=== Test 1: Get commits for PR #151615 ===")
    try:
        result1 = client.execute_query(
            query1,
            {
                "owner": org,
                "name": repo,
                "number": pr_number,
            },
        )
        print("Result keys:", sorted(result1.keys()))

        if "repository" in result1:
            print("✓ Repository found")
            repo_data = result1["repository"]
            if "pullRequest" in repo_data:
                print("✓ PullRequest found")
                pr_data = repo_data["pullRequest"]
                if "commits" in pr_data:
                    commits_data = pr_data["commits"]
                    nodes = commits_data.get("nodes", [])
                    print(f"✓ Found {len(nodes)} commits")
                    for commit in nodes:
                        print(f"  - SHA: {commit.get('oid')}")
                        print(f"  - Message: {commit.get('message', '')[:50]}...")
                        parents = commit.get("parents", {})
                        parent_nodes = parents.get("nodes", [])
                        print(f"  - Parents: {[p.get('oid') for p in parent_nodes]}")
                else:
                    print("✗ No commits in PullRequest")
            else:
                print("✗ No pullRequest in repository")
        else:
            print("✗ No repository in result")

        if "errors" in result1:
            print(f"⚠ Errors: {result1['errors']}")
    except Exception as e:
        print(f"❌ Exception: {eRepr()}")

    # Test 2: Search for PRs (verify main query syntax)
    query2 = """
    query($query: String!, $first: Int!, $after: String) {
      search(query: $query, type: ISSUE, first: $first, after: $after) {
        edges {
          node {
            ... on PullRequest {
              number
              title
              mergedAt
              mergeCommit {
                oid
              }
              baseRef {
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
    """

    print("\n=== Test 2: Search for PRs ===")
    try:
        result2 = client.execute_query(
            query2,
            {
                "query": "repo:rust-lang/rust is:pr is:merged",
                "first": 1,
                "after": None,
            },
        )
        print("Result keys:", sorted(result2.keys()))

        if "search" in result2:
            print("✓ Search found")
            search_data = result2["search"]
            edges = search_data.get("edges", [])
            if edges:
                print(f"✓ Found {len(edges)} edges")
                for edge in edges:
                    node = edge.get("node", {})
                    if node:
                        print(f"  - PR #{node.get('number')}")
                        print(f"  - Title: {node.get('title', '')[:50]}...")

                        merge_commit = node.get("mergeCommit", {})
                        print(f"  - mergeCommit type: {type(merge_commit)}")
                        print(
                            f"  - mergeCommit keys: {sorted(merge_commit.keys()) if isinstance(merge_commit, dict) else 'not a dict'}"
                        )

                        base_ref = node.get("baseRef", {})
                        print(f"  - baseRef type: {type(base_ref)}")
                        print(
                            f"  - baseRef keys: {sorted(base_ref.keys()) if isinstance(base_ref, dict) else 'not a dict'}"
                        )
            else:
                print("✗ No edges in search")

        if "errors" in result2:
            print(f"⚠ Errors: {result2['errors']}")
    except Exception as e:
        print(f"❌ Exception: {eRepr()}")


if __name__ == "__main__":
    main()
