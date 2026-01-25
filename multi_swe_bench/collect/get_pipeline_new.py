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
import re
from pathlib import Path

from multi_swe_bench.collect.build_dataset import main as build_dataset
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

    return parser


def run_pipeline(
    out_dir: Path,
    tokens: list[str],
    org: str,
    repo: str,
    delay_on_error: int = 300,
    retry_attempts: int = 3,
) -> None:
    print(f"\n{'=' * 60}")
    print(f"Processing: {org}/{repo}")
    print(f"{'=' * 60}")

    print("\n=== Step 1: Fetch related issues ===")
    filtered_file = out_dir / f"{org}__{repo}_filtered_prs.jsonl"
    print("Filtered file:", filtered_file)
    get_related_issues(tokens, out_dir, filtered_file)

    print("\n=== Step 2: Merge PRs + Issues ===")
    merge_prs_with_issues(out_dir, org, repo)

    print("\n=== Step 3: Build Dataset ===")
    dataset_file = out_dir / f"{org}__{repo}_filtered_prs_with_issues.jsonl"
    print("Dataset file:", dataset_file)
    build_dataset(tokens, out_dir, dataset_file, delay_on_error, retry_attempts)

    print("\n=== Pipeline Completed Successfully ===")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()
    tokens = get_tokens(args.tokens)

    out_dir = args.out_dir

    print(f"Scanning directory: {out_dir}")
    filtered_files = list(out_dir.glob("*_filtered_prs.jsonl"))

    if not filtered_files:
        print(f"No *_filtered_prs.jsonl files found in {out_dir}")
        exit(0)

    print(f"Found {len(filtered_files)} files to process")

    filename_pattern = re.compile(r"(.+)__(.+)_filtered_prs\.jsonl$")

    for filtered_file in filtered_files:
        m = filename_pattern.match(filtered_file.name)
        if not m:
            print(f"Warning: Could not parse filename: {filtered_file.name}")
            continue

        org = m.group(1)
        repo = m.group(2)

        run_pipeline(
            out_dir=out_dir,
            tokens=tokens,
            org=org,
            repo=repo,
            delay_on_error=args.delay_on_error,
            retry_attempts=args.retry_attempts,
        )
