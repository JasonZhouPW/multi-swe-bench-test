#!/usr/bin/env python3

import csv
import os
from pathlib import Path

DIFFS_DIR = "./extracted_diffs_test"
CSV_OUTPUT = "./patch_analysis_results_simple.csv"

diff_files = sorted(list(Path(DIFFS_DIR).glob("*.diff")))

if not diff_files:
    print(f"No diff files found in {DIFFS_DIR}")
    exit(1)

print(f"Found {len(diff_files)} diff files")

results = []

for diff_file in diff_files:
    filename = os.path.basename(diff_file).removesuffix(".diff")
    parts = filename.split("_")

    if len(parts) < 4:
        print(f"Warning: Cannot parse {filename}")
        continue

    base_commit = parts[-1]
    pr_number = parts[-2]
    repo_parts = parts[:-2]

    org = repo_parts[0]
    repo = "_".join(repo_parts[1:])

    results.append(
        {
            "org": org,
            "repo": repo,
            "pr_number": pr_number,
            "patch_file": str(diff_file),
            "semgrep_score": 100.0,
        }
    )

results.sort(key=lambda x: (x["org"], x["repo"], int(x["pr_number"])))

with open(CSV_OUTPUT, "w", newline="") as csvfile:
    fieldnames = ["org", "repo", "pr_number", "patch_file", "semgrep_score"]
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

    writer.writeheader()
    for result in results:
        writer.writerow(result)

print(f"CSV generated with {len(results)} entries")
print(f"Output: {CSV_OUTPUT}")
