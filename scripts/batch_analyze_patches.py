#!/usr/bin/env python3
import csv
import os
import subprocess
import sys
from pathlib import Path

PATCHES_DIR = "./extracted_patches_from_javads"
SEMGREP_OUTPUT_DIR = "./semgrep_results"
CSV_OUTPUT = "./patch_analysis_results.csv"

os.makedirs(SEMGREP_OUTPUT_DIR, exist_ok=True)


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


def run_semgrep_on_patch_file(patch_file_path, output_file):
    try:
        result = subprocess.run(
            [
                "semgrep",
                "scan",
                "--config=auto",
                "--json",
                f"--output={output_file}",
                str(patch_file_path),
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print(f"Timeout scanning {patch_file_path.name}")
        return False
    except Exception as e:
        print(f"Error scanning {patch_file_path.name}: {e}")
        return False


def main():
    patch_files = sorted(list(Path(PATCHES_DIR).glob("*.patch")))

    if not patch_files:
        print(f"No patch files found in {PATCHES_DIR}")
        return 1

    print(f"Found {len(patch_files)} patch files to scan...")

    results = []

    for idx, patch_file in enumerate(patch_files, 1):
        org, repo, pr_number = parse_patch_filename(patch_file)
        if not all([org, repo, pr_number]):
            print(f"Warning: Could not parse {patch_file.name}")
            continue

        output_file = os.path.join(SEMGREP_OUTPUT_DIR, f"{org}_{repo}_{pr_number}.json")

        sys.stdout.flush()

        if run_semgrep_on_patch_file(patch_file, output_file):
            import json

            with open(output_file, "r") as f:
                semgrep_data = json.load(f)
            findings_count = len(semgrep_data.get("results", []))

            results.append(
                {
                    "org": org,
                    "repo": repo,
                    "pr_number": pr_number,
                    "patch_file": str(patch_file),
                    "semgrep_result": output_file,
                    "findings_count": findings_count,
                }
            )
        else:
            print(f"Failed to scan {patch_file.name}")
            continue

        if idx % 20 == 0 or idx == len(patch_files):
            print(
                f"Processed {idx}/{len(patch_files)} patches ({len(results)} successful)"
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

    print(f"\nCompleted! Processed {len(results)} patches.")
    print(f"Results saved to {CSV_OUTPUT}")
    print(f"Semgrep detailed results saved to {SEMGREP_OUTPUT_DIR}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
