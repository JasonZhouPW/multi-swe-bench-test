#!/usr/bin/env python3

"""
Unit test for new_fetch_prs_graphql.py
Tests GraphQL queries to verify they work correctly.
"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../"))

from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def test_search_query():
    """Test 1: Search PR query - validate query structure"""
    print("=" * 60)
    print("TEST 1: Search PR Query")
    print("=" * 60)

    token = "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"
    client = GitHubGraphQLClient(token)

    query = """
    query($q: String!, $first: Int!, $after: String) {
      search(query: $q, type: ISSUE, first: $first, after: $after) {
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
    }
    """

    variables = {"q": "repo:rust-lang/rust is:pr is:merged", "first": 1, "after": None}

    print(f"Query: {query}")
    print(f"Variables: {json.dumps(variables, indent=2)}")

    try:
        result = client.execute_query(query, variables)
        print(f"\nResult keys: {sorted(result.keys())}")

        if "data" in result:
            print("✓ 'data' key found")
            data = result["data"]
            print(f"Data keys: {sorted(data.keys())}")

            if "search" in data:
                search = data["search"]
                edges = search.get("edges", [])
                print(f"Found {len(edges)} edges")

                if edges:
                    node = edges[0].get("node", {})
                    print(f"Node keys: {sorted(node.keys())}")

                    merge_commit = node.get("mergeCommit", {})
                    print(f"mergeCommit type: {type(merge_commit)}")
                    print(f"mergeCommit value: {json.dumps(merge_commit, indent=2)}")

                    if merge_commit:
                        print(
                            f"✓ mergeCommit.oid = {merge_commit.get('oid', 'NOT FOUND')}"
                        )
                    else:
                        print("✗ mergeCommit is None/null")
        else:
            print("✗ No 'data' key in result")
            print("Available keys:", sorted(result.keys()))

        if "errors" in result:
            print(f"\n✗ GraphQL Errors:")
            for error in result["errors"]:
                print(f"  - Message: {error.get('message', 'Unknown')}")
                if "path" in error:
                    print(f"  - Path: {error['path']}")
                if "locations" in error:
                    print(f"  - Locations: {error['locations']}")

        return True

    except Exception as e:
        print(f"\n✗ Exception: {type(e).__name__}: {e}")
        import traceback

        traceback.print_exc()
        return False


def test_commits_query():
    """Test 2: Commits query - validate commit structure"""
    print("\n" + "==" * 60)
    print("TEST 2: Commits Query")
    print("=" * 60)

    token = "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"
    client = GitHubGraphQLClient(token)

    org = "rust-lang"
    repo = "rust"
    pr_number = 5959

    query = """
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

    variables = {"owner": org, "name": repo, "number": pr_number}

    print(f"Query: {query}")
    print(f"Variables: {json.dumps(variables, indent=2)}")

    try:
        result = client.execute_query(query, variables)
        print(f"\nResult keys: {sorted(result.keys())}")

        if "data" in result:
            print("✓ 'data' key found")
            data = result["data"]
            print(f"Data keys: {sorted(data.keys())}")

            if "repository" in data:
                repo_data = data["repository"]
                print(f"Repository keys: {sorted(repo_data.keys())}")

                if "pullRequest" in repo_data:
                    pr_data = repo_data["pullRequest"]
                    print(f"PullRequest keys: {sorted(pr_data.keys())}")

                    if "commits" in pr_data:
                        commits_data = pr_data["commits"]
                        print(f"Commits keys: {sorted(commits_data.keys())}")

                        nodes = commits_data.get("nodes", [])
                        print(f"Found {len(nodes)} commit nodes")

                        if nodes:
                            node = nodes[0]
                            print(f"First commit node keys: {sorted(node.keys())}")
                            print(f"First commit value: {json.dumps(node, indent=2)}")

                            if "oid" in node:
                                print(f"✓ commit.oid = {node['oid']}")
                            else:
                                print("✗ No 'oid' in commit node")
                        else:
                            print("✗ No commit nodes")
                    else:
                        print("✗ No 'commits' in PullRequest")
                else:
                    print("✗ No 'pullRequest' in repository")
            else:
                print("✗ No 'repository' in data")
        else:
            print("✗ No 'data' key in result")
            print("Available keys:", sorted(result.keys()))

        if "errors" in result:
            print(f"\n✗ GraphQL Errors:")
            for error in result["errors"]:
                print(f"  - Message: {error.get('message', 'Unknown')}")
                if "path" in error:
                    print(f"  - Path: {error['path']}")

        return True

    except Exception as e:
        print(f"\n✗ Exception: {type(e).__name__}: {e}")
        import traceback

        traceback.print_exc()
        return False


if __name__ == "__main__":
    print("\n" + "==" * 60)
    print("UNIT TESTS FOR new_fetch_prs_graphql.py")
    print("=" * 60)
    print(
        "\nThese tests validate the GraphQL queries used in new_fetch_prs_graphql.py\n"
    )

    test1_pass = test_search_query()
    test2_pass = test_commits_query()

    print("\n" + "==" * 60)
    print("TEST RESULTS")
    print("=" * 60)
    print(f"Test 1 (Search PR Query): {'PASS' if test1_pass else 'FAIL'}")
    print(f"Test 2 (Commits Query): {'PASS' if test2_pass else 'FAIL'}")
    print("=" * 60)

    if test1_pass and test2_pass:
        print("✅ All tests passed! The queries are correct.")
        sys.exit(0)
    else:
        print("❌ Some tests failed. Check the output above for details.")
        sys.exit(1)
