#!/usr/bin/env python3
import argparse
import csv
import json
import os
import subprocess
import re
import sys
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Batch analyze diff files with semgrep"
    )
    parser.add_argument(
        "diffs_dir",
        help="Directory containing .diff files to analyze"
    )
    return parser.parse_args()


def parse_diff_filename(filename):
    filename_without_extension = os.path.basename(filename).removesuffix(".diff")
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


def extract_score_from_analyze_output(output_text):
    match = re.search(r"Final Score:\s*(\d+(?:\.\d+)?)\s*/\s*100", output_text)
    if match:
        return float(match.group(1))
    return None


def main():
    args = parse_args()
    
    diffs_dir = args.diffs_dir
    semgrep_results_dir = os.path.join(diffs_dir, "semgrep_results")
    csv_output = os.path.join(diffs_dir, "semgrep_result.csv")
    
    os.makedirs(semgrep_results_dir, exist_ok=True)
    
    diff_files = sorted(list(Path(diffs_dir).glob("*.diff")))

    if not diff_files:
        print(f"No diff files found in {diffs_dir}")
        return 1

    print(f"Found {len(diff_files)} diff files to analyze...")
    print("Step 1: Running batch semgrep scan...")

    batch_output = os.path.join(semgrep_results_dir, "batch_all.json")
    result = subprocess.run(
        [
            "semgrep",
            "scan",
            "--config=auto",
            "--json",
            f"--output={batch_output}",
            diffs_dir,
        ],
        capture_output=True,
        text=True,
        timeout=180,
    )

    if result.returncode != 0:
        print(f"Semgrep scan failed: {result.stderr}")
        return 1

    print(f"Semgrep scan completed. Loading results...")

    with open(batch_output, "r") as f:
        batch_data = json.load(f)

    results_by_file = {}
    for res in batch_data.get("results", []):
        path = res.get("path", "")
        if path not in results_by_file:
            results_by_file[path] = []
        results_by_file[path].append(res)

    print(f"Processing results for {len(diff_files)} files...")

    results = []

    for idx, diff_file in enumerate(diff_files, 1):
        org, repo, pr_number = parse_diff_filename(diff_file)
        if not all([org, repo, pr_number]):
            print(f"Warning: Could not parse {diff_file.name}")
            continue

        semgrep_json = os.path.join(
            semgrep_results_dir, f"{org}_{repo}_{pr_number}.json"
        )
        findings = results_by_file.get(str(diff_file), [])

        individual_result = {
            "version": batch_data.get("version", "1.0.0"),
            "results": findings,
            "errors": [],
            "paths": {"scanned": [str(diff_file)]},
            "engine_requested": batch_data.get("engine_requested", "OSS"),
        }

        with open(semgrep_json, "w") as f:
            json.dump(individual_result, f, indent=2)

        analyze_output = subprocess.run(
            ["bash", "./scripts/analyze_patch.sh", semgrep_json],
            capture_output=True,
            text=True,
            timeout=10,
        )

        if analyze_output.returncode == 0:
            score = extract_score_from_analyze_output(analyze_output.stdout)
            if score is None:
                score = 100.0
        else:
            print(f"Warning: analyze_patch.sh failed for {diff_file.name}")
            score = 100.0

        results.append(
            {
                "org": org,
                "repo": repo,
                "pr_number": pr_number,
                "patch_file": str(diff_file),
                "semgrep_score": score,
            }
        )

        if idx % 50 == 0 or idx == len(diff_files):
            print(
                f"Processed {idx}/{len(diff_files)} patches ({len(results)} successful)"
            )

    results.sort(key=lambda x: (x["org"], x["repo"], int(x["pr_number"])))

    with open(csv_output, "w", newline="") as csvfile:
        fieldnames = ["org", "repo", "pr_number", "patch_file", "semgrep_score"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()
        for result in results:
            writer.writerow(result)

    print(f"\nCompleted! Processed {len(results)} patches.")
    print(f"Results saved to {csv_output}")

    score_stats = {}
    for r in results:
        score = r["semgrep_score"]
        if score == 100:
            bucket = "100 (Excellent)"
        elif score >= 90:
            bucket = "90-99 (A)"
        elif score >= 80:
            bucket = "80-89 (B)"
        elif score >= 70:
            bucket = "70-79 (C)"
        elif score >= 60:
            bucket = "60-69 (D)"
        else:
            bucket = "<60 (F)"

        score_stats[bucket] = score_stats.get(bucket, 0) + 1

    print(f"\nScore Distribution:")
    for bucket, count in sorted(
        score_stats.items(), key=lambda x: -float(x[0].split()[0])
    ):
        print(f"  {bucket}: {count}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
