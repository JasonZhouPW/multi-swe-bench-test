#!/usr/bin/env python3

import csv
import json
import os
import subprocess
import sys
from pathlib import Path

DIFFS_DIR = "./test_patch"
CSV_OUTPUT = "./patch_analysis_results.csv"
SEMGREP_BATCH_OUTPUT = "./semgrep_batch_results.json"

diff_files = sorted(list(Path(DIFFS_DIR).glob("*.diff")))

if not diff_files:
    print(f"No diff files found in {DIFFS_DIR}")
    sys.exit(1)

print(f"Found {len(diff_files)} diff files")
print("Running batch semgrep scan...")

result = subprocess.run(
    [
        "semgrep",
        "scan",
        "--config=auto",
        "--json",
        f"--output={SEMGREP_BATCH_OUTPUT}",
        DIFFS_DIR,
    ],
    capture_output=True,
    text=True,
    timeout=300,
)

if result.returncode != 0:
    print(f"Warning: Semgrep scan returned code {result.returncode}")

results_by_file = {}

if os.path.exists(SEMGREP_BATCH_OUTPUT):
    with open(SEMGREP_BATCH_OUTPUT, "r") as f:
        try:
            semgrep_data = json.load(f)
            for res in semgrep_data.get("results", []):
                path = res.get("path", "")
                severity = res.get("extra", {}).get("severity", "INFO")
                message = res.get("message", res.get("extra", {}).get("message", ""))
                check_id = res.get("check_id", "")
                start_line = res.get("start", {}).get("line", None)
                if path not in results_by_file:
                    results_by_file[path] = {
                        "ERROR": 0,
                        "WARNING": 0,
                        "INFO": 0,
                        "details": [],
                    }
                results_by_file[path][severity] += 1
                results_by_file[path]["details"].append(
                    {
                        "severity": severity,
                        "message": message,
                        "check_id": check_id,
                        "start_line": start_line,
                    }
                )
        except json.JSONDecodeError:
            print("Warning: Failed to parse semgrep output")


def calculate_score(errors, warnings, infos):
    base_score = 100
    deduction = (errors * 10) + (warnings * 2) + (infos * 0.5)
    return max(0, base_score - deduction)


def generate_comments(errors, warnings, infos, details):
    if errors > 0:
        parts = [f"CRITICAL: {errors} error(s) found. Patch rejected."]
        for detail in details:
            msg = detail["message"]
            start_line = detail.get("start_line")
            if msg:
                line_info = f" (line {start_line})" if start_line else ""
                parts.append(f" - {msg}{line_info}")
        return "; ".join(parts)
    elif warnings > 0:
        deduction = warnings * 2
        parts = [f"WARNING: {warnings} warning(s) found. (-{deduction})"]
        for detail in details[:5]:
            msg = detail["message"]
            start_line = detail.get("start_line")
            if msg:
                line_info = f" (line {start_line})" if start_line else ""
                parts.append(f" - {msg}{line_info}")
        if warnings > 5:
            parts.append(f" ... and {warnings - 5} more")
        return "; ".join(parts)
    elif infos > 0:
        deduction = infos * 0.5
        parts = [f"INFO: {infos} info finding(s). (-{deduction})"]
        for detail in details[:3]:
            msg = detail["message"]
            start_line = detail.get("start_line")
            if msg:
                line_info = f" (line {start_line})" if start_line else ""
                parts.append(f" - {msg}{line_info}")
        if infos > 3:
            parts.append(f" ... and {infos - 3} more")
        return "; ".join(parts)
    else:
        return ""


results = []

for diff_file in diff_files:
    filename = os.path.basename(diff_file).removesuffix(".diff")
    parts = filename.split("_")

    if len(parts) < 4:
        continue

    base_commit = parts[-1]
    pr_number = parts[-2]
    repo_parts = parts[:-2]

    org = repo_parts[0]
    repo = "_".join(repo_parts[1:])

    findings_dict = results_by_file.get(
        str(diff_file), {"ERROR": 0, "WARNING": 0, "INFO": 0, "details": []}
    )
    errors = findings_dict.get("ERROR", 0)
    warnings = findings_dict.get("WARNING", 0)
    infos = findings_dict.get("INFO", 0)
    details = findings_dict.get("details", [])

    score = calculate_score(errors, warnings, infos)
    comments = generate_comments(errors, warnings, infos, details)

    results.append(
        {
            "org": org,
            "repo": repo,
            "pr_number": pr_number,
            "patch_file": str(diff_file),
            "semgrep_score": score,
            "comments": comments,
        }
    )

results.sort(key=lambda x: (x["org"], x["repo"], int(x["pr_number"])))

with open(CSV_OUTPUT, "w", newline="") as csvfile:
    fieldnames = ["org", "repo", "pr_number", "patch_file", "semgrep_score", "comments"]
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

    writer.writeheader()
    for result in results:
        writer.writerow(result)

print(f"CSV generated with {len(results)} entries")
print(f"Output: {CSV_OUTPUT}")

score_distribution = {}
for r in results:
    score_range = int(r["semgrep_score"] / 10) * 10
    key = f"{score_range}-{score_range + 9}"
    score_distribution[key] = score_distribution.get(key, 0) + 1

print("\nScore Distribution:")
for score_range in sorted(score_distribution.keys()):
    print(f"  {score_range}: {score_distribution[score_range]} entries")
