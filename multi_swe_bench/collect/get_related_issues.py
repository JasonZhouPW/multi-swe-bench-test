# Copyright (c) 2024 Bytedance Ltd. and/or its affiliates

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

import argparse
import json
import random
import re
import sys
from pathlib import Path

import requests
from github import Auth, Github
from tqdm import tqdm

from multi_swe_bench.collect.util import get_tokens, make_request_with_retry


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="A command-line tool for processing repositories."
    )
    parser.add_argument(
        "--out_dir", type=Path, required=True, help="Output directory path."
    )
    parser.add_argument(
        "--tokens",
        type=str,
        nargs="*",
        default=None,
        help="API token(s) or path to token file.",
    )
    parser.add_argument(
        "--filtered_prs_file", type=Path, required=True, help="Path to pull file."
    )

    return parser


def get_github(token) -> Github:
    auth = Auth.Token(token)
    return Github(auth=auth, per_page=100)


def get_top_repositories(g: Github, language=None, limit=10):
    query = "stars:>1"
    if language:
        query += f" language:{language}"

    # Search repositories and sort by stars
    result = g.search_repositories(query=query, sort="stars", order="desc")

    top_repos = []
    for repo in result[:limit]:
        top_repos.append((repo.full_name, repo.stargazers_count))

    return top_repos


def main(tokens, out_dir: Path, filtered_prs_file: Path):
    print("starting get all related issues")
    print(f"Output directory: {out_dir}")
    print(f"Tokens: {tokens}")
    print(f"Pull file: {filtered_prs_file}")

    org_repo_re = re.compile(r"(.+)__(.+)_filtered_prs.jsonl")
    m = org_repo_re.match(filtered_prs_file.name)
    if not m:
        print(f"Error: Invalid pull file name: {filtered_prs_file.name}")
        sys.exit(1)

    org = m.group(1)
    repo = m.group(2)
    print(f"Org: {org}")
    print(f"Repo: {repo}")

    with open(filtered_prs_file, "r", encoding="utf-8") as file:
        filtered_prs = [json.loads(line) for line in file]

    # --------------------------
    # 分离真实 issue 与占位 issue
    # --------------------------
    target_issues = set()
    placeholder_issues = []

    for pr in filtered_prs:
        for issue_number in pr["resolved_issues"]:
            if issue_number == -1:
                # 占位 issue
                placeholder_issues.append(
                    {
                        "org": org,
                        "repo": repo,
                        "number": -1,
                        "state": "unknown",
                        "title": pr.get("title", ""),
                        "body": pr.get("body", ""),
                    }
                )
            else:
                target_issues.add(issue_number)

    tk = random.choice(tokens)
    g = get_github(tk)
    r = g.get_repo(f"{org}/{repo}")

    headers = {
        "Accept": "application/vnd.github.v3+json",
        "Authorization": f"token {tk}",
    }

    with open(
        out_dir / f"{org}__{repo}_related_issues.jsonl", "w", encoding="utf-8"
    ) as out_file:
        # Write placeholder issues
        for issue in placeholder_issues:
            out_file.write(json.dumps(issue, ensure_ascii=False) + "\n")

        if not target_issues:
            print("No real target issues to fetch.")
            return

        # Fetch issues in chunks via Search API to avoid long URLs
        target_list = sorted(list(target_issues))
        chunk_size = 50
        pbar = tqdm(total=len(target_list), desc="Issues")
        for i in range(0, len(target_list), chunk_size):
            chunk = target_list[i : i + chunk_size]
            # Build query like: repo:org/repo is:issue number:123 number:456 ...
            query_parts = [f"repo:{org}/{repo}", "is:issue"]
            for num in chunk:
                query_parts.append(f"number:{num}")
            query = " ".join(query_parts)

            url = f"https://api.github.com/search/issues?q={query}"

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
            resp.raise_for_status()
            data = resp.json()
            items = data.get("items", [])
            for item in items:
                out_file.write(
                    json.dumps(
                        {
                            "org": org,
                            "repo": repo,
                            "number": item["number"],
                            "state": item["state"],
                            "title": item["title"],
                            "body": item["body"],
                        },
                        ensure_ascii=False,
                    )
                    + "\n",
                )
            pbar.update(len(chunk))
        pbar.close()


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)

    main(tokens, Path.cwd() / args.out_dir, args.filtered_prs_file)
