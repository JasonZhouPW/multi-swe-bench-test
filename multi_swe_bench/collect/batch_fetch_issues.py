# Copyright (c) 2024 Bytedance Ltd. and/or its affiliates

# 1.  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
# 2.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

import argparse
import json
import re
import random
import requests
from pathlib import Path
from tqdm import tqdm

from multi_swe_bench.collect.util import get_tokens, make_request_with_retry


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Batch fetch related issues from filtered PRs and save merged results."
    )
    parser.add_argument(
        "--src_dir",
        type=Path,
        required=True,
        help="Source directory containing _filtered_prs.jsonl files.",
    )
    parser.add_argument(
        "--out_dir",
        type=Path,
        required=False,
        help="Output directory for filtered_prs_with_issues.jsonl files. "
        "If not provided, uses src_dir.",
    )
    parser.add_argument(
        "--tokens",
        type=str,
        nargs="*",
        default=None,
        help="API token(s) or path to token file.",
    )
    parser.add_argument(
        "--chunk_size",
        type=int,
        default=50,
        help="Number of issues to fetch per API request (default: 50).",
    )

    return parser


def main(src_dir: Path, out_dir: Path, tokens: list[str], chunk_size: int = 50):
    """
    Process all _filtered_prs.jsonl files in src_dir:
    1. Read PRs and collect all issue numbers from resolved_issues
    2. Fetch issue details from GitHub API
    3. Replace issue numbers with full issue objects
    4. Save to filtered_prs_with_issues.jsonl
    """
    if out_dir is None:
        out_dir = src_dir

    out_dir.mkdir(parents=True, exist_ok=True)

    filtered_files = list(src_dir.glob("*_filtered_prs.jsonl"))

    if not filtered_files:
        print(f"No _filtered_prs.jsonl files found in {src_dir}")
        return

    print(f"Found {len(filtered_files)} files to process in {src_dir}")

    for filtered_file in filtered_files:
        print(f"\nProcessing: {filtered_file.name}")

        filename_re = re.compile(r"(.+)__(.+)_filtered_prs.jsonl")
        m = filename_re.match(filtered_file.name)
        if not m:
            print(
                f"Warning: Could not parse org/repo from filename: {filtered_file.name}"
            )
            continue

        org = m.group(1)
        repo = m.group(2)
        print(f"  Org: {org}, Repo: {repo}")

        with open(filtered_file, "r", encoding="utf-8") as file:
            prs = [json.loads(line) for line in file]

        print(f"  Found {len(prs)} PRs")

        all_issue_numbers = set()
        for pr in prs:
            if "resolved_issues" in pr and pr["resolved_issues"]:
                for issue_number in pr["resolved_issues"]:
                    if issue_number != -1:
                        all_issue_numbers.add(issue_number)

        print(f"  Unique issues to fetch: {len(all_issue_numbers)}")

        if not all_issue_numbers:
            print(f"  No real issues to fetch (only placeholders or none)")
            output_file = out_dir / f"{org}__{repo}_filtered_prs_with_issues.jsonl"
            with open(output_file, "w", encoding="utf-8") as out_file:
                for pr in prs:
                    out_file.write(json.dumps(pr, ensure_ascii=False) + "\n")
            continue

        issues_dict = {}
        target_list = sorted(list(all_issue_numbers))

        tk = random.choice(tokens)
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {tk}",
        }

        print(f"  Fetching issues from GitHub API...")
        pbar = tqdm(total=len(target_list), desc="  Issues")

        for i in range(0, len(target_list), chunk_size):
            chunk = target_list[i : i + chunk_size]

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
                issues_dict[item["number"]] = {
                    "org": org,
                    "repo": repo,
                    "number": item["number"],
                    "state": item["state"],
                    "title": item["title"],
                    "body": item["body"],
                }

            pbar.update(len(chunk))

        pbar.close()
        print(f"  Successfully fetched {len(issues_dict)} issues")

        output_file = out_dir / f"{org}__{repo}_filtered_prs_with_issues.jsonl"
        print(f"  Writing to: {output_file.name}")

        with open(output_file, "w", encoding="utf-8") as out_file:
            for pr in tqdm(prs, desc="  Writing"):
                if "resolved_issues" not in pr:
                    out_file.write(json.dumps(pr, ensure_ascii=False) + "\n")
                    continue

                resolved_issues = []
                for issue_number in pr["resolved_issues"]:
                    if issue_number == -1:
                        resolved_issues.append(
                            {
                                "org": org,
                                "repo": repo,
                                "number": -1,
                                "state": "unknown",
                                "title": pr.get("title", ""),
                                "body": pr.get("body", ""),
                            }
                        )
                    elif issue_number in issues_dict:
                        resolved_issues.append(issues_dict[issue_number])

                pr["resolved_issues"] = resolved_issues
                out_file.write(json.dumps(pr, ensure_ascii=False) + "\n")

        print(f"  Completed: {output_file.name}")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)

    main(
        src_dir=args.src_dir,
        out_dir=args.out_dir,
        tokens=tokens,
        chunk_size=args.chunk_size,
    )
