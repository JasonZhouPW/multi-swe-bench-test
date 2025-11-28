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
from pathlib import Path

from multi_swe_bench.collect.build_dataset import main as build_dataset
from multi_swe_bench.collect.filter_prs import main as filter_prs
from multi_swe_bench.collect.get_all_prs import main as get_all_prs
from multi_swe_bench.collect.get_related_issues import main as get_related_issues
from multi_swe_bench.collect.merge_prs_with_issues import main as merge_prs_with_issues
from multi_swe_bench.collect.util import get_tokens, optional_int


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
    parser.add_argument("--org", type=str, required=False, help="Organization name.")
    parser.add_argument("--repo", type=str, required=False, help="Repository name.")
    parser.add_argument(
        "--delay-on-error",
        type=optional_int,
        default=300,
        help="Delay in seconds before retrying on error. If none, exit on error.",
    )
    parser.add_argument(
        "--retry-attempts",
        type=int,
        default=3,
        help="Number of attempts to retry on error.",
    )
    parser.add_argument(
        "--skip-commit-message",
        type=bool,
        default=False,
        help="Skip commit message.",
    )

    return parser


def run_pipeline(
    out_dir: Path,
    tokens: list[str],
    org: str,
    repo: str,
    delay_on_error: int = 300,
    retry_attempts: int = 3,
    skip_commit_message: bool = False,
    key_words: str = None,
) -> None:

    out_dir.mkdir(parents=True, exist_ok=True)

    print("\n=== Step 1: Fetch all PRs ===")
    get_all_prs(tokens, out_dir, org, repo)

    # Step 1.5: 根据 key_words 筛选并覆盖原始 PR 文件
    pull_file = out_dir / f"{org}__{repo}_prs.jsonl"

    if key_words:
        print(f"\n=== Step 1.5: Filter PRs by keyword: '{key_words}' (overwrite original file) ===")
        key_lower = key_words.lower()
        # 读取原始文件
        with open(pull_file, "r", encoding="utf-8") as fin:
            lines = [line for line in fin if key_lower in line.lower()]
        
        # 覆盖写回原始文件
        with open(pull_file, "w", encoding="utf-8") as fout:
            fout.writelines(lines)

        print(f"Keyword filtered PRs overwritten to original file: {pull_file}")    


    print("\n=== Step 2: Filter PRs ===")
    pull_file = out_dir / f"{org}__{repo}_prs.jsonl"
    print("Pull file:", pull_file)
    filter_prs(tokens, out_dir, pull_file, skip_commit_message)

    print("\n=== Step 3: Fetch related issues ===")
    filtered_file = out_dir / f"{org}__{repo}_filtered_prs.jsonl"
    print("Filtered file:", filtered_file)
    get_related_issues(tokens, out_dir, filtered_file)

    print("\n=== Step 4: Merge PRs + Issues ===")
    merge_prs_with_issues(out_dir, org, repo)

    print("\n=== Step 5: Build Dataset ===")
    dataset_file = out_dir / f"{org}__{repo}_filtered_prs_with_issues.jsonl"
    print("Dataset file:", dataset_file)
    build_dataset(tokens, out_dir, dataset_file, delay_on_error, retry_attempts)

    print("\n=== Pipeline Completed Successfully ===")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()
    tokens = get_tokens(args.tokens)

    run_pipeline(
        out_dir=args.out_dir,
        tokens=tokens,
        org=args.org,
        repo=args.repo,
        delay_on_error=args.delay_on_error,
        retry_attempts=args.retry_attempts,
        skip_commit_message=args.skip_commit_message,
    )
