#!/usr/bin/env python3

import json
import os

patches = [
    (
        "alibaba/nacos #14056 (Score: 99.5)",
        "./extracted_diffs/alibaba_nacos_14056_ebe37b47f2796337fd6ba3c400ac3cffdfd88524.diff",
        "extracted_diffs/alibaba_nacos_14056_ebe37b47f2796337fd6ba3c400ac3cffdfd88524_semgrep.json",
    ),
    (
        "apache/incubator #7882 (Score: 99.5)",
        "./extracted_diffs/apache_incubator_7882_576c6b39b6d3e8a38a4a3022735dffc2e6fc9136.diff",
        "extracted_diffs/apache_incubator_7882_576c6b39b6d3e8a38a4a3022735dffc2e6fc9136_semgrep.json",
    ),
    (
        "apache/incubator #7893 (Score: 99.5)",
        "./extracted_diffs/apache_incubator_7893_76ea767b57d6c26fdad634f8d52fcb1c008f816a.diff",
        "extracted_diffs/apache_incubator_7893_76ea767b57d6c26fdad634f8d52fcb1c008f816a_semgrep.json",
    ),
    (
        "apache/incubator #7909 (Score: 99.5)",
        "./extracted_diffs/apache_incubator_7909_7eedf68d51e5aa2a9a919d91b59f1feff6c247d9.diff",
        "extracted_diffs/apache_incubator_7909_7eedf68d51e5aa2a9a919d91b59f1feff6c247d9_semgrep.json",
    ),
]

for title, patch_file, output_file in patches:
    print(f"\n{'=' * 80}")
    print(f"{title}")
    print(f"{'=' * 80}")
    print(f"Patch file: {patch_file}")
    print(f"Semgrep output: {output_file}")

    if not os.path.exists(output_file):
        print(f"\nError: Semgrep output file not found: {output_file}")
        continue

    with open(output_file, "r") as f:
        data = json.load(f)

    results = data.get("results", [])
    print(f"\nTotal findings: {len(results)}")

    if results:
        print(f"\n{'─' * 80}")
        print("Findings details:")
        print(f"{'─' * 80}")
        for i, r in enumerate(results[:10], 1):
            severity = r.get("extra", {}).get("severity", "INFO")
            check_id = r.get("check_id", "unknown")
            message = r.get("message", r.get("extra", {}).get("message", ""))[:100]
            file_path = r.get("path", "")

            print(f"\n  Finding {i}:")
            print(f"    Check ID: {check_id}")
            print(f"    Severity: {severity}")
            print(f"    File: {file_path}")
            print(f"    Message: {message}")

        if len(results) > 10:
            print(f"\n  ... and {len(results) - 10} more findings")
    else:
        print("\nNo findings found.")
