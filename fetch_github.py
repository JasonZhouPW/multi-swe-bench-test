#!/usr/bin/env python3
"""
Fetch GitHub issue and PR data and output in multi-swe-bench format.

Usage:
    python fetch_github.py <issue_url> <pr_url> [output_file]

Example:
    python fetch_github.py https://github.com/moby/moby/issues/51651 https://github.com/moby/moby/pull/51843
"""

import argparse
import json
import re
import sys
import time
import urllib.request
import urllib.error
from typing import Dict, List, Optional, Any, Callable
from urllib.parse import urlparse


def make_urllib_request_with_retry(
    request_func: Callable[[], urllib.request.Request],
    max_retries: int = 5,
    initial_backoff: float = 1.0,
    backoff_multiplier: float = 2.0,
    max_backoff: float = 60.0,
    verbose: bool = True,
):
    """
    Wrapper for urllib requests with exponential backoff retry for rate limiting.
    """
    last_error = None

    for attempt in range(max_retries):
        try:
            req = request_func()
            with urllib.request.urlopen(req) as response:
                return response
        except urllib.error.HTTPError as e:
            if e.code == 429:
                last_error = Exception(f"HTTP 429: Rate limit exceeded")
            elif e.code == 403:
                last_error = Exception(f"HTTP 403: Forbidden (possibly rate limit)")
            else:
                raise e
        except Exception as e:
            last_error = e

        if last_error and attempt < max_retries - 1:
            backoff_time = min(
                initial_backoff * (backoff_multiplier**attempt), max_backoff
            )
            if verbose:
                print(
                    f"Rate limit hit (attempt {attempt + 1}/{max_retries}). "
                    f"Waiting {backoff_time:.1f} seconds before retry..."
                )
            time.sleep(backoff_time)
        else:
            raise last_error

    raise last_error if last_error else Exception("Request failed after retries")


def parse_github_url(url: str) -> Optional[Dict[str, Any]]:
    """Parse GitHub URL to extract org, repo, number, and type."""
    patterns = [
        r"https://github\.com/([^/]+)/([^/]+)/issues/(\d+)",
        r"https://github\.com/([^/]+)/([^/]+)/pull/(\d+)",
    ]

    for pattern in patterns:
        match = re.match(pattern, url)
        if match:
            org, repo, number = match.groups()
            item_type = "issue" if "issues" in url else "pull"
            return {"org": org, "repo": repo, "number": int(number), "type": item_type}
    return None


def fetch_from_github(
    api_url: str, token: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """Fetch data from GitHub API with rate limit handling."""
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "pull-github/1.0",
    }
    if token:
        headers["Authorization"] = f"token {token}"

    def make_request():
        return urllib.request.Request(api_url, headers=headers)

    try:
        with make_urllib_request_with_retry(
            make_request,
            max_retries=5,
            initial_backoff=1.0,
            backoff_multiplier=2.0,
            max_backoff=60.0,
            verbose=True,
        ) as response:
            data = response.read().decode("utf-8")
            return json.loads(data)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"Error: Resource not found: {api_url}")
        elif e.code == 403:
            print(f"Error: Rate limit exceeded or access forbidden")
            print("Consider using --token to increase rate limit")
        else:
            print(f"Error fetching {api_url}: {e.code}")
    except urllib.error.URLError as e:
        print(f"Error fetching {api_url}: {e.reason}")
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON response: {e}")

    return None


def fetch_issue(
    org: str, repo: str, number: int, token: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """Fetch issue data from GitHub."""
    api_url = f"https://api.github.com/repos/{org}/{repo}/issues/{number}"
    return fetch_from_github(api_url, token)


def fetch_pr(
    org: str, repo: str, number: int, token: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """Fetch PR data from GitHub."""
    api_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{number}"
    return fetch_from_github(api_url, token)


def fetch_commits(
    org: str, repo: str, pr_number: int, token: Optional[str] = None
) -> List[Dict[str, Any]]:
    """Fetch commits for a PR."""
    api_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/commits"
    result = fetch_from_github(api_url, token)
    if isinstance(result, list):
        return result
    return []


def fetch_pr_files(
    org: str, repo: str, pr_number: int, token: Optional[str] = None
) -> List[Dict[str, Any]]:
    """Fetch files changed in a PR."""
    api_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/files"
    result = fetch_from_github(api_url, token)
    if isinstance(result, list):
        return result
    return []


def fetch_full_diff(
    org: str, repo: str, pr_number: int, token: Optional[str] = None
) -> str:
    """Fetch complete diff from GitHub with rate limit handling."""
    diff_url = f"https://github.com/{org}/{repo}/pull/{pr_number}.diff"
    headers = {"User-Agent": "pull-github/1.0"}
    if token:
        headers["Authorization"] = f"token {token}"

    def make_request():
        return urllib.request.Request(diff_url, headers=headers)

    try:
        with make_urllib_request_with_retry(
            make_request,
            max_retries=5,
            initial_backoff=1.0,
            backoff_multiplier=2.0,
            max_backoff=60.0,
            verbose=True,
        ) as response:
            return response.read().decode("utf-8")
    except Exception as e:
        print(f"Error fetching diff: {e}")
        return ""


def is_test_file(filename: str) -> bool:
    test_indicators = [
        "_test.go",
        "_test.py",
        "_test.rb",
        "_test.js",
        "test/",
        "tests/",
        "spec/",
        "specs/",
        "__tests__/",
        "test_",
        "tests_",
    ]
    filename_lower = filename.lower()
    return any(indicator in filename_lower for indicator in test_indicators)


def construct_jsonl_entry(
    pr_data: Dict[str, Any],
    resolved_issues: List[Dict[str, Any]],
    token: Optional[str] = None,
) -> Dict[str, Any]:
    """Construct a JSONL entry in multi-swe-bench format."""

    org = pr_data["base"]["repo"]["owner"]["login"]
    repo = pr_data["base"]["repo"]["name"]
    pr_number = pr_data["number"]

    commits = fetch_commits(org, repo, pr_number, token)
    commits_list = []
    for commit in commits:
        commits_list.append(
            {
                "sha": commit["sha"],
                "parents": [p["sha"] for p in commit.get("parents", [])],
                "message": commit["commit"]["message"],
            }
        )

    files = fetch_pr_files(org, repo, pr_number, token)

    full_diff = fetch_full_diff(org, repo, pr_number, token)
    fix_diff_parts = []
    test_diff_parts = []

    diff_blocks = full_diff.split("\ndiff --git ")
    for i, block in enumerate(diff_blocks):
        if not block:
            continue

        if i > 0:
            block = "diff --git " + block

        for file_data in files:
            filename = file_data["filename"]
            if filename in block:
                if is_test_file(filename):
                    test_diff_parts.append(block)
                else:
                    fix_diff_parts.append(block)
                break

    fix_patch = "\n".join(fix_diff_parts)
    if fix_patch and not fix_patch.endswith("\n"):
        fix_patch += "\n"

    test_patch = "\n".join(test_diff_parts)
    if test_patch and not test_patch.endswith("\n"):
        test_patch += "\n"

    entry = {
        "org": org,
        "repo": repo,
        "number": pr_number,
        "state": pr_data["state"],
        "title": pr_data["title"],
        "body": pr_data["body"] or "",
        "url": pr_data["url"],
        "id": pr_data["id"],
        "node_id": pr_data["node_id"],
        "html_url": pr_data["html_url"],
        "diff_url": pr_data["diff_url"],
        "patch_url": pr_data["patch_url"],
        "issue_url": pr_data["issue_url"],
        "created_at": pr_data["created_at"],
        "updated_at": pr_data["updated_at"],
        "closed_at": pr_data.get("closed_at"),
        "merged_at": pr_data.get("merged_at"),
        "merge_commit_sha": pr_data.get("merge_commit_sha"),
        "labels": [label["name"] for label in pr_data.get("labels", [])],
        "draft": pr_data.get("draft", False),
        "commits_url": pr_data["commits_url"],
        "review_comments_url": pr_data["review_comments_url"],
        "review_comment_url": pr_data["review_comment_url"],
        "comments_url": pr_data["comments_url"],
        "base": pr_data["base"],
        "commits": commits_list,
        "resolved_issues": resolved_issues,
        "fix_patch": fix_patch,
        "test_patch": test_patch,
    }

    return entry


def main():
    parser = argparse.ArgumentParser(
        description="Fetch GitHub issue and PR data in multi-swe-bench format"
    )
    parser.add_argument("issue_url", help="GitHub issue URL")
    parser.add_argument("pr_url", help="GitHub PR URL")
    parser.add_argument(
        "output_file", nargs="?", help="Output JSONL file path (default: output.jsonl)"
    )
    parser.add_argument(
        "--token", help="GitHub personal access token (optional, increases rate limit)"
    )

    args = parser.parse_args()

    issue_info = parse_github_url(args.issue_url)
    pr_info = parse_github_url(args.pr_url)

    if not issue_info:
        print(f"Error: Invalid issue URL: {args.issue_url}")
        sys.exit(1)

    if not pr_info:
        print(f"Error: Invalid PR URL: {args.pr_url}")
        sys.exit(1)

    if issue_info["type"] != "issue":
        print(f"Error: First URL must be an issue, not a {issue_info['type']}")
        sys.exit(1)

    if pr_info["type"] != "pull":
        print(f"Error: Second URL must be a PR, not a {pr_info['type']}")
        sys.exit(1)

    print(
        f"Fetching issue {issue_info['org']}/{issue_info['repo']}#{issue_info['number']}..."
    )
    issue_data = fetch_issue(
        issue_info["org"], issue_info["repo"], int(issue_info["number"]), args.token
    )
    if not issue_data:
        print("Failed to fetch issue")
        sys.exit(1)

    print(f"Fetching PR {pr_info['org']}/{pr_info['repo']}#{pr_info['number']}...")
    pr_data = fetch_pr(
        pr_info["org"], pr_info["repo"], int(pr_info["number"]), args.token
    )
    if not pr_data:
        print("Failed to fetch PR")
        sys.exit(1)

    resolved_issues = [
        {
            "org": issue_info["org"],
            "repo": issue_info["repo"],
            "number": issue_data["number"],
            "state": issue_data["state"],
            "title": issue_data["title"],
            "body": issue_data["body"] or "",
        }
    ]

    print("Constructing JSONL entry...")
    entry = construct_jsonl_entry(pr_data, resolved_issues, args.token)

    output_file = args.output_file or "output.jsonl"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(entry, f, ensure_ascii=False)
        f.write("\n")

    print(f"Successfully wrote output to {output_file}")


if __name__ == "__main__":
    main()
