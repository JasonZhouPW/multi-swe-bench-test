#!/usr/bin/env python3
import csv
import json
import os
from pathlib import Path

SEMGREP_OUTPUT_DIR = "./semgrep_results"
CSV_OUTPUT = "./patch_analysis_results.csv"


def parse_result_filename(filename):
    filename_without_extension = os.path.basename(filename).removesuffix(".json")
    parts = filename_without_extension.split("_")

    if len(parts) < 3:
        return None, None, None

    pr_number = None
    org = None
    repo = None

    for i in range(len(parts) - 1, 0, -1):
        if parts[i].isdigit():
            pr_number = parts[i]
            repo_parts = parts[:i]
            org = repo_parts[0]
            repo = "_".join(repo_parts[1:])
            break

    return org, repo, pr_number


def main():
    patch_dir = "./extracted_patches_from_javads"
    results_files = list(Path(SEMGREP_OUTPUT_DIR).glob("*.json"))

    if not results_files:
        print("No semgrep results found")
        return 1

    print(f"Found {len(results_files)} semgrep result files")

    results = []

    for result_file in results_files:
        org, repo, pr_number = parse_result_filename(result_file)
        if not all([org, repo, pr_number]):
            continue

        patch_file = os.path.join(patch_dir, f"{org}_{repo}_{pr_number}.patch")

        findings_count = 0
        if os.path.exists(result_file):
            with open(result_file, "r") as f:
                try:
                    semgrep_data = json.load(f)
                    findings_count = len(semgrep_data.get("results", []))
                except json.JSONDecodeError:
                    pass

        results.append(
            {
                "org": org,
                "repo": repo,
                "pr_number": pr_number,
                "patch_file": patch_file,
                "semgrep_result": str(result_file),
                "findings_count": findings_count,
            }
        )

    results.sort(key=lambda x: (x["org"], x["repo"], int(x["pr_number"])))

    with open(CSV_OUTPUT, "w", newline="") as csvfile:
        fieldnames = [
            "org",
            "repo",
            "pr_number",
            "patch_file",
            "semgrep_result",
            "findings_count",
        ]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()
        for result in results:
            writer.writerow(result)

    print(f"\nCSV generated with {len(results)} entries")
    print(f"Output: {CSV_OUTPUT}")

    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
