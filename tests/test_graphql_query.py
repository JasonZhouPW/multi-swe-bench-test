#!/usr/bin/env python3
"""
Simple test script for GraphQL PR search
"""

import sys
import os

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from multi_swe_bench.collect.util import get_tokens
from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def test_graphql_query():
    # Test query string
    query_string = (
        "repo:mark3labs/mcp-go is:pr is:merged merged:>2025-12-31 merged:<2026-01-05"
    )

    print("Testing GraphQL query construction:")
    print(f"Query string: {query_string}")
    print()

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

    variables = {"query": query_string, "first": 10, "after": None}

    print("GraphQL Query:")
    print(query.strip())
    print()
    print("Variables:")
    print(variables)
    print()

    # Get tokens and actually call GitHub
    tokens = get_tokens(["./data_pipeline/tokens.txt"])
    if not tokens:
        print("❌ No tokens found")
        return

    token = tokens[0]
    print(f"✅ Using token: {token[:10]}...")

    # Create GraphQL client
    client = GitHubGraphQLClient(token)

    try:
        print("🔄 Calling GitHub GraphQL API...")
        result = client.execute_query(query, variables)
        print("\n📊 GraphQL API Response:")
        print("=" * 60)

        if "errors" in result:
            print("❌ GraphQL Errors:")
            for error in result["errors"]:
                print(f"  - {error.get('message', 'Unknown error')}")
            return

        search_data = result.get("search", {})
        edges = search_data.get("edges", [])
        page_info = search_data.get("pageInfo", {})

        print(f"✅ Found {len(edges)} PRs")
        print(f"📄 Has next page: {page_info.get('hasNextPage', False)}")

        if edges:
            print("\n📋 PR Details:")
            print("-" * 60)
            for i, edge in enumerate(edges, 1):
                node = edge.get("node", {})
                if node:
                    print(f"{i}. PR #{node.get('number')}")
                    print(f"   📝 Title: {node.get('title', 'N/A')}")
                    print(f"   🔄 State: {node.get('state', 'N/A')}")
                    print(f"   📅 Created: {node.get('createdAt', 'N/A')}")
                    print(f"   ✅ Merged: {node.get('mergedAt', 'N/A')}")
                    print(f"   🔗 URL: {node.get('url', 'N/A')}")
                    print()

        print("🔍 Raw response structure:")
        import json

        print(json.dumps(result, indent=2))

    except Exception as e:
        print(f"❌ Error calling GitHub API: {e}")
        print("Possible causes:")
        print("  - Invalid or expired token")
        print("  - Network connectivity issues")
        print("  - Rate limiting")
        print("  - Invalid repository or query syntax")


if __name__ == "__main__":
    test_graphql_query()
