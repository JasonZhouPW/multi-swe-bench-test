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
import json
import random
import re
import requests
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from tqdm import tqdm

from multi_swe_bench.collect.util import get_tokens, make_request_with_retry
from multi_swe_bench.collect.fetch_github_repo_gql import GitHubGraphQLClient


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="A command-line tool for processing repositories."
    )
    parser.add_argument(
        "--input", type=Path, required=True, help="Input CSV file with repositories."
    )
    parser.add_argument(
        "--output", type=Path, required=True, help="Output JSONL file for PRs."
    )
    parser.add_argument(
        "--tokens",
        type=str,
        nargs="*",
        default=None,
        help="API token(s) or path to token file.",
    )

    parser.add_argument(
        "--created_at",
        type=str,
        required=False,
        default=None,
        help="Filter PRs created after this datetime (ISO format).",
    )
    parser.add_argument(
        "--merged_after",
        type=str,
        required=False,
        default=None,
        help="Filter PRs merged after this datetime (ISO format).",
    )
    parser.add_argument(
        "--merged_before",
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
    parser.add_argument(
        "--skip-commit-message",
        type=bool,
        default=False,
        help="Skip fetching commit messages.",
    )
    return parser


def extract_resolved_issues(pull: dict) -> list[int]:
    """
    判断 PR 是否解决/关联 issue。
    - 如果 title/body/commit 包含 fix/close/resolve + #num → 返回 issue number
    - 如果 title/body/labels 包含关键字（refactor/ref/...）但没有 #num → 返回 -1 作为占位
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


def is_relevant_pull(pull, key_words: Optional[str] = None) -> bool:
    """
    判断 PR 是否可能是修复 issue 的 PR。
    """

    title = pull.title.lower() if pull.title else ""
    labels = [label.name.lower() for label in pull.labels]

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
    if pull.body and any(k in pull.body.lower() for k in keywords):
        return True

    return False


def main(
    tokens: list[str],
    input_csv: Path,
    output_jsonl: Path,
    created_at: Optional[str] = None,
    key_words: Optional[str] = None,
    merged_after: Optional[str] = None,
    merged_before: Optional[str] = None,
    skip_commit_message: bool = False,
):
    print("starting get all pull requests")
    print(f"Input CSV: {input_csv}")
    print(f"Output JSONL: {output_jsonl}")
    print(f"Tokens: {tokens}")
    print(f"Created At: {created_at}")
    print(f"Merged After: {merged_after}")
    print(f"Merged Before: {merged_before}")
    print(f"Key Words: {key_words}")
    print(f"Skip Commit Message: {skip_commit_message}")

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

    filter_dt = None
    if created_at:
        try:
            created_at_clean = created_at.replace("Z", "+00:00")
            dt = datetime.fromisoformat(created_at_clean)
        except ValueError:
            raise ValueError(f"Invalid created_at format: {created_at}")
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        filter_dt = dt

    merged_dt = None
    if merged_after:
        try:
            merged_after_clean = merged_after.replace("Z", "+00:00")
            md = datetime.fromisoformat(merged_after_clean)
        except ValueError:
            raise ValueError(f"Invalid merged_after format: {merged_after}")
        if md.tzinfo is None:
            md = md.replace(tzinfo=timezone.utc)
        merged_dt = md

    merged_before_dt = None
    if merged_before:
        try:
            merged_before_clean = merged_before.replace("Z", "+00:00")
            mb = datetime.fromisoformat(merged_before_clean)
        except ValueError:
            raise ValueError(f"Invalid merged_before format: {merged_before}")
        if mb.tzinfo is None:
            mb = mb.replace(tzinfo=timezone.utc)
        merged_before_dt = mb

    print("token:", tokens)
    if tokens:
        tk = random.choice(tokens)
        print("Using token:", tk)
    else:
        tk = None
        print(
            "No tokens available. GitHub API will be called without Authorization header."
        )

    def datetime_serializer(obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return obj

    total_prs = 0
    with open(output_jsonl, "w", encoding="utf-8") as file:
        for org, repo in repositories:
            print(f"Processing repository: {org}/{repo}")

            headers = {"Accept": "application/vnd.github.v3+json"}
            if tk:
                headers["Authorization"] = f"{tk}"

            base_query_parts = [f"repo:{org}/{repo}", "is:pr", "is:merged"]

            if merged_after:
                base_query_parts.append(f" merged:>={merged_after}")
            if merged_before:
                base_query_parts.append(f" merged:<={merged_before}")
            if key_words is not None and key_words != "":
                for kw in key_words.split(","):
                    kw_clean = kw.strip()
                    if kw_clean:
                        base_query_parts.append(f'"{kw_clean}"')
            query = " ".join(base_query_parts)

            base_url = f"https://api.github.com/search/issues?q={query}&sort=updated&order=desc&per_page=100"

            url = base_url
            fetched = 0
            while url:
                print(f"url:{url}")

                def make_search_request():
                    return requests.get(url, headers=headers)

                resp = make_request_with_retry(
                    make_search_request,
                    max_retries=5,
                    initial_backoff=1.0,
                    backoff_multiplier=2.0,
                    max_backoff=60.0,
                    verbose=True,
                )

                print(f"resp:{resp}")
                resp.raise_for_status()
                data = resp.json()
                items = data.get("items", [])

                for item in items:
                    pr_number = item["number"]
                    try:
                        pr_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}"

                        def make_pr_request():
                            return requests.get(pr_url, headers=headers)

                        pr_resp = make_request_with_retry(
                            make_pr_request,
                            max_retries=5,
                            initial_backoff=1.0,
                            backoff_multiplier=2.0,
                            max_backoff=60.0,
                            verbose=True,
                        )
                        pr_resp.raise_for_status()
                        pr_data = pr_resp.json()

                        base_obj = pr_data.get("base", {})
                        if "sha" not in base_obj:
                            print(
                                f"Warning: PR #{pr_number} base object missing sha: {list(base_obj.keys())}"
                            )

                        commits_list = pr_data.get("commits", [])
                        if not commits_list and not skip_commit_message:
                            print(f"Warning: PR #{pr_number} commits list is empty")

                    except Exception as e:
                        print(f"Failed to fetch PR #{pr_number} details: {e}")
                        continue

                    created_at_dt = datetime.fromisoformat(
                        pr_data["created_at"].replace("Z", "+00:00")
                    )
                    merged_at_dt = pr_data.get("merged_at")
                    if merged_at_dt:
                        merged_at_dt = datetime.fromisoformat(
                            merged_at_dt.replace("Z", "+00:00")
                        )

                    if filter_dt is not None and created_at_dt <= filter_dt:
                        print(
                            f"Skipping PR #{pr_number} created at {created_at_dt}, required after {filter_dt}"
                        )
                        continue

                    if merged_dt is not None and (
                        merged_at_dt is None or merged_at_dt <= merged_dt
                    ):
                        print(
                            f"Skipping PR #{pr_number} merged at {merged_at_dt}, required after {merged_dt}"
                        )
                        continue

                    if (
                        merged_before_dt is not None
                        and merged_at_dt
                        and merged_at_dt >= merged_before_dt
                    ):
                        print(
                            f"Skipping PR #{pr_number} merged at {merged_at_dt}, required before {merged_before_dt}"
                        )
                        continue

                    if key_words is not None and key_words != "":

                        class MockLabel:
                            def __init__(self, name):
                                self.name = name

                        class MockPull:
                            def __init__(self, data):
                                self.title = data.get("title", "")
                                self.body = data.get("body", "")
                                self.labels = [
                                    MockLabel(label["name"])
                                    for label in data.get("labels", [])
                                ]

                        mock_pull = MockPull(pr_data)
                        if not is_relevant_pull(mock_pull, key_words):
                            print(f"Skipping PR #{pr_number} not matching keywords")
                            continue

                    print(
                        f"Get PR #{pr_number} created at {created_at_dt} merged at {merged_at_dt}"
                    )

                    commits_data = []
                    if not skip_commit_message and commits_list:
                        commits_data = [
                            {
                                "sha": commit.get("sha"),
                                "parents": [
                                    p.get("sha") for p in commit.get("parents", [])
                                ],
                                "message": commit.get("commit", {}).get("message", ""),
                            }
                            for commit in commits_list
                        ]

                    resolved_issues = extract_resolved_issues(
                        {
                            "title": pr_data.get("title", ""),
                            "body": pr_data.get("body", ""),
                            "commits": commits_data,
                        }
                    )

                    file.write(
                        json.dumps(
                            {
                                "org": org,
                                "repo": repo,
                                "number": pr_data["number"],
                                "state": pr_data["state"],
                                "title": pr_data["title"],
                                "body": pr_data["body"],
                                "url": pr_data["url"],
                                "id": pr_data["id"],
                                "node_id": pr_data["node_id"],
                                "html_url": pr_data["html_url"],
                                "diff_url": pr_data["diff_url"],
                                "patch_url": pr_data["patch_url"],
                                "issue_url": pr_data["issue_url"],
                                "created_at": pr_data["created_at"],
                                "updated_at": pr_data["updated_at"],
                                "closed_at": pr_data["closed_at"],
                                "merged_at": pr_data["merged_at"],
                                "merge_commit_sha": pr_data["merge_commit_sha"],
                                "labels": [
                                    label["name"] for label in pr_data.get("labels", [])
                                ],
                                "draft": pr_data.get("draft", False),
                                "commits": commits_data,
                                "resolved_issues": resolved_issues,
                                "commits_url": pr_data["commits_url"],
                                "review_comments_url": pr_data["review_comments_url"],
                                "review_comment_url": pr_data["review_comment_url"],
                                "comments_url": pr_data["comments_url"],
                                "base": pr_data["base"],
                            },
                            ensure_ascii=False,
                        )
                        + "\n"
                    )
                    fetched += 1
                    total_prs += 1

                if "next" in resp.links:
                    url = resp.links["next"]["url"]
                else:
                    url = None

            print(f"Fetched {fetched} merged PRs from {org}/{repo}")

    print(f"Total PRs fetched: {total_prs}")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)

    main(
        tokens,
        args.input,
        args.output,
        args.created_at,
        args.key_words,
        args.merged_after,
        args.merged_before,
        args.skip_commit_message,
    )
