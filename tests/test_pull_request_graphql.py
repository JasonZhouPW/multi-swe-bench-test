"""
Unit test for GitHub GraphQL PullRequest object fields.
Tests that all common PullRequest fields can be fetched successfully.
"""

import os
import re
import sys
import json
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


class TestPullRequestGraphQL(unittest.TestCase):
    """Test GitHub GraphQL API PullRequest object fields."""

    def setUp(self):
        """Set up test by loading GitHub token."""
        tokens_file = Path(__file__).parent.parent / "data_pipeline" / "tokens.txt"

        if not tokens_file.exists():
            self.skipTest(f"Token file not found: {tokens_file}")

        with open(tokens_file, "r") as f:
            token = f.read().strip()

        if not token:
            self.skipTest("No token found in tokens.txt")

        self.client = GitHubGraphQLClient(token)

    def test_pull_request_all_fields(self):
        """Test fetching a PullRequest with all common fields."""
        org = "python"
        repo = "cpython"
        pr_number = 144209

        query = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              id
              number
              title
              body
              state
              isDraft

              createdAt
              updatedAt
              closedAt
              mergedAt

              url
              resourcePath

              baseRef {
                name
                prefix
                target {
                  ... on Commit {
                    oid
                  }
                }
              }
              headRef {
                name
                prefix
              }

              repository {
                name
                nameWithOwner
                url
              }

              author {
                login
                url
                avatarUrl
              }

              mergeCommit {
                oid
                abbreviatedOid
                message
              }
              mergeable
              mergedBy {
                login
              }

              labels(first: 10) {
                nodes {
                  name
                  color
                  description
                }
              }

              commits(first: 10) {
                nodes {
                  commit {
                    oid
                    messageHeadline
                    committedDate
                    author {
                      user {
                        login
                      }
                    }
                  }
                }
              }

              reviews(first: 10) {
                nodes {
                  state
                  author {
                    login
                  }
                  submittedAt
                }
              }

              additions
              deletions

              comments(first: 10) {
                totalCount
                nodes {
                  body
                  createdAt
                  author {
                    login
                  }
                }
              }

              participants(first: 10) {
                nodes {
                  login
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

        result = self.client.execute_query(query, variables)

        self.assertIn("repository", result)
        self.assertIn("pullRequest", result["repository"])

        pr = result["repository"]["pullRequest"]
        self.assertIsNotNone(pr, "PullRequest not found")

        self.assertIsNotNone(pr.get("id"))
        self.assertEqual(pr["number"], pr_number)
        self.assertIsNotNone(pr.get("title"))
        self.assertIn(pr["state"], ["OPEN", "CLOSED", "MERGED"])

        self.assertIsNotNone(pr.get("createdAt"))
        self.assertIsNotNone(pr.get("updatedAt"))

        self.assertIsNotNone(pr.get("url"))

        self.assertIsNotNone(pr.get("baseRef"))
        # headRef may be None if the head branch was deleted after merge

        # Base commit hash
        base_ref = pr.get("baseRef", {})
        base_target = base_ref.get("target", {})
        base_commit_hash = base_target.get("oid")
        self.assertIsNotNone(base_commit_hash, "Base commit hash should be available")
        print(f"   Base commit hash: {base_commit_hash[:10]}...")

        self.assertIsNotNone(pr.get("repository"))

        self.assertIsNotNone(pr.get("author"))

        self.assertIn("labels", pr)

        self.assertIn("commits", pr)

        self.assertIn("reviews", pr)

        self.assertIsInstance(pr.get("additions"), int)
        self.assertIsInstance(pr.get("deletions"), int)

        self.assertIn("comments", pr)

        self.assertIn("participants", pr)

        # Extract related issue numbers from PR body, commits, and comments
        pr_body = pr.get("body", "")
        commits_nodes = pr.get("commits", {}).get("nodes", [])
        comments_nodes = pr.get("comments", {}).get("nodes", [])

        issue_pattern = re.compile(r"#(\d+)")
        issue_refs = set()

        for match in issue_pattern.finditer(pr_body):
            issue_refs.add(int(match.group(1)))

        for commit in commits_nodes:
            commit_msg = commit.get("commit", {}).get("messageHeadline", "")
            for match in issue_pattern.finditer(commit_msg):
                issue_refs.add(int(match.group(1)))

        for comment in comments_nodes:
            comment_body = comment.get("body", "")
            for match in issue_pattern.finditer(comment_body):
                issue_refs.add(int(match.group(1)))

        print(
            f"   Related issues found: {sorted(issue_refs) if issue_refs else 'None'}"
        )

        self.assertIsInstance(issue_refs, set)

        print(f"\n✅ Successfully fetched PR #{pr_number}: {pr['title']}")
        print(f"   State: {pr['state']}, Merged: {pr.get('mergedAt') is not None}")
        print(f"   Changes: +{pr['additions']}/-{pr['deletions']}")

        return pr

    def test_pull_request_simple_fields(self):
        """Test fetching a PullRequest with minimal fields."""
        org = "python"
        repo = "cpython"
        pr_number = 144209

        query = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              number
              title
              state
              url
            }
          }
        }
        """

        variables = {
            "owner": org,
            "name": repo,
            "number": pr_number,
        }

        result = self.client.execute_query(query, variables)

        pr = result["repository"]["pullRequest"]
        self.assertEqual(pr["number"], pr_number)
        self.assertIsNotNone(pr["title"])
        self.assertIsNotNone(pr["url"])

        print(f"\n✅ Simple query successful: PR #{pr['number']}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
