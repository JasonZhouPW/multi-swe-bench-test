#!/usr/bin/env python3
"""
Test script for enhanced new_fetch_prs_graphql.py
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from multi_swe_bench.collect.new_fetch_prs_graphql import search_prs_with_graphql
from multi_swe_bench.collect.util import get_tokens


def test_fetch_prs():
    """Test the updated PR fetching with base commit hash and related issues."""
    print("🧪 Testing Enhanced PR Fetching")

    tokens = get_tokens(["./data_pipeline/tokens.txt"])
    if not tokens:
        print("❌ No tokens found")
        return 1

    client = GitHubGraphQLClient(tokens[0])

    # Test with a known Go repository
    org = "golang"
    repo = "go"

    print(f"Testing with repository: {org}/{repo}")

    # Fetch a few PRs
    prs = search_prs_with_graphql(
        client=client,
        org=org,
        repo=repo,
        max_results=3,  # Just test 3 PRs
    )

    print(f"\n📊 Results:")
    print(f"Fetched {len(prs)} PRs")

    for pr in prs:
        print(f"\n📋 PR #{pr.get('number')}")
        print(f"  Title: {pr.get('title', 'N/A')[:50]}...")
        print(f"  State: {pr.get('state')}")
        print(f"  Base commit hash: {pr.get('base_commit_hash', 'N/A')}")
        print(f"  Related issues: {pr.get('related_issues', [])}")
        print(f"  Merged: {'Yes' if pr.get('merged_at') else 'No'}")

    return 0 if prs else 1


if __name__ == "__main__":
    sys.exit(test_fetch_prs())
