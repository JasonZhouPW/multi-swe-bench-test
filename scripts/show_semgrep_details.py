#!/usr/bin/env python3

import json
import subprocess

patches = [
    "alibaba_nacos_14056_ebe37b47f2796337fd6ba3c400ac3cffdfd88524",
    "apache_incubator_7882_576c6b39b6d3e8a38a4a3022735dffc2e6fc9136",
    "apache_incubator_7893_76ea767b57d6c26fdad634f8d52fcb1c008f816a",
    "apache_incubator_7909_7eedf68d51e5aa2a9a919d91b59f1feff6c247d9",
]

for patch_name in patches:
    diff_file = f"extracted_diffs/{patch_name}.diff"
    print(f"\n{'=' * 80}")
    print(f"Patch: {patch_name}")
    print(f"{'=' * 80}")

    result = subprocess.run(
        ["semgrep", "scan", "--config=auto", "--json", diff_file],
        capture_output=True,
        text=True,
        timeout=60,
    )

    if result.returncode == 0:
        data = json.loads(result.stdout)
        results = data.get("results", [])
        print(f"\nTotal findings: {len(results)}")

        if results:
            print(f"\n{'─' * 80}")
            print("Findings details:")
            print(f"{'─' * 80}")
            for i, r in enumerate(results, 1):
                severity = r.get("extra", {}).get("severity", "INFO")
                check_id = r.get("check_id", "unknown")
                message = r.get("message", r.get("extra", {}).get("message", ""))[:100]
                file_path = r.get("path", "")
                line = r.get("start", {}).get("line", "N/A")
                code_line = r.get("lines", "")

                print(f"\n  Finding {i}:")
                print(f"    Check ID: {check_id}")
                print(f"    Severity: {severity}")
                print(f"    Line: {line}")
                print(f"    File: {file_path}")
                print(f"    Message: {message}")
                if code_line:
                    print(f"    Code: {code_line[:150]}")
        else:
            print("\nNo findings found.")
    else:
        print(f"\nError: {result.stderr}")
