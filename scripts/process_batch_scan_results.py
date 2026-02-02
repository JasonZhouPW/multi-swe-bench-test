#!/usr/bin/env python3
import csv
import json
import os
import shutil
from pathlib import Path

PATCHES_DIR = "./extracted_patches_from_javads"
SEMGREP_OUTPUT_DIR = "./semgrep_results"
CSV_OUTPUT = "./patch_analysis_results.csv"

BATCH_RESULT_FILE = os.path.join(SEMGREP_OUTPUT_DIR, "batch_all.json")


def parse_patch_filename(filename):
    filename_without_extension = os.path.basename(filename).removesuffix(".patch")
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
    patch_files = sorted(list(Path(PATCHES_DIR).glob("*.patch")))

    if not patch_files:
        print(f"No patch files found in {PATCHES_DIR}")
        return 1

    print(f"Processing {len(patch_files)} patch files...")

    results = []

    batch_data = {}
    if os.path.exists(BATCH_RESULT_FILE):
        with open(BATCH_RESULT_FILE, "r") as f:
            batch_data = json.load(f)

    results_by_file = {}
    for result in batch_data.get("results", []):
        path = result.get("path", "")
        findings_list = results_by_file.setdefault(path, [])
        findings_list.append(result)

    for patch_file in patch_files:
        org, repo, pr_number = parse_patch_filename(patch_file)
        if not all([org, repo, pr_number]):
            print(f"Warning: Could not parse {patch_file.name}")
            continue

        output_file = os.path.join(SEMGREP_OUTPUT_DIR, f"{org}_{repo}_{pr_number}.json")
        findings = results_by_file.get(str(patch_file), [])

        individual_result = {
            "version": batch_data.get("version", "1.0.0"),
            "results": findings,
            "errors": [],
            "paths": {"scanned": [str(patch_file)]},
            "engine_requested": batch_data.get("engine_requested", "OSS"),
        }

        with open(output_file, "w") as f:
            json.dump(individual_result, f, indent=2)

        results.append(
            {
                "org": org,
                "repo": repo,
                "pr_number": pr_number,
                "patch_file": str(patch_file),
                "semgrep_result": output_file,
                "findings_count": len(findings),
            }
        )

        if len(results) % 50 == 0:
            print(f"Processed {len(results)} patches...")

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

    print(f"\nCompleted! Processed {len(results)} patches.")
    print(f"Results saved to {CSV_OUTPUT}")
    print(f"Semgrep detailed results saved to {SEMGREP_OUTPUT_DIR}/")

    summary = {}
    for result in results:
        org_name = f"{result['org']}/{result['repo']}"
        summary[org_name] = summary.get(org_name, 0) + 1

    print(f"\nPatches per repository:")
    for repo, count in sorted(summary.items()):
        print(f"  {repo}: {count}")

    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
