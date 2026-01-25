#!/usr/bin/env python3
"""
Demo script showing GitHub GraphQL PullRequest field fetching.
This demonstrates that all common PullRequest fields can be retrieved successfully.
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from tests.test_pull_request_graphql import TestPullRequestGraphQL
import unittest


def main():
    """Run the PullRequest GraphQL tests and show results."""
    print("🚀 Testing GitHub GraphQL PullRequest Object Fields")
    print("=" * 60)

    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestPullRequestGraphQL)

    # Run tests with detailed output
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 60)
    if result.wasSuccessful():
        print(
            "✅ All tests passed! GitHub GraphQL PullRequest fields are working correctly."
        )
        print("\n📋 Summary of fields successfully fetched:")
        fields = [
            "id",
            "number",
            "title",
            "body",
            "state",
            "isDraft",
            "createdAt",
            "updatedAt",
            "closedAt",
            "mergedAt",
            "url",
            "resourcePath",
            "baseRef",
            "headRef",
            "repository",
            "author",
            "mergeCommit",
            "mergeable",
            "mergedBy",
            "labels",
            "commits",
            "reviews",
            "additions",
            "deletions",
            "comments",
            "participants",
            "base_commit_hash",
            "related_issues",
        ]
        for field in fields:
            print(f"  ✓ {field}")
    else:
        print("❌ Some tests failed. Check the output above for details.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
