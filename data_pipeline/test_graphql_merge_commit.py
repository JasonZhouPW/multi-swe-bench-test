#!/usr/bin/env python3

from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def main():
    token = "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"
    client = GitHubGraphQLClient(token)

    org = "rust-lang"
    repo = "rust"
    pr_number = 151615

    # Test: Check mergeCommit structure in PR search
    query = """
    query($query: String!, $first: Int!, $after: String) {
      search(query: $query, type: ISSUE, first: $first, after: $after) {
        edges {
          node {
            ... on PullRequest {
              number
              mergedAt
              mergeCommit {
                oid
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

    print("=== Test: Check mergeCommit structure ===")
    print(f"Query: {query}")

    variables = {
        "query": f"repo:{org}/{repo} is:pr is:merged",
        "first": 3,
        "after": None,
    }

    try:
        result = client.execute_query(query, variables)
        print("Result keys:", sorted(result.keys()))

        if "search" in result:
            print("Search found")
            search_data = result["search"]
            edges = search_data.get("edges", [])

            for i, edge in enumerate(edges, 1):
                node = edge.get("node", {})
                if node:
                    print(f"Edge {i}: PR #{node.get('number')}")
                    merge_commit = node.get("mergeCommit", {})
                    print(f"  - mergeCommit type: {type(merge_commit)}")
                    print(
                        f"  - mergeCommit keys: {sorted(merge_commit.keys()) if isinstance(merge_commit, dict) else 'not a dict'}"
                    )

                    if merge_commit and isinstance(merge_commit, dict):
                        print(f"  - Has 'oid': {'oid' in merge_commit}")
        else:
            print("No search in result")

        if "errors" in result:
            print(f"Errors: {result['errors']}")

    except Exception as e:
        print(f"Exception: {eRepr()}")


if __name__ == "__main__":
    main()
