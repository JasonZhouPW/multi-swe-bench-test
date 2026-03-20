#!/usr/bin/env python3
"""
Quick verification report checker.

This script reads existing report.json files and provides a summary
of AI-generated fix-patch verification results.

Usage:
    python scripts/check_verification_report.py <report.json>
    python scripts/check_verification_report.py --dir verify_output/
"""

import argparse
import json
import os
import sys
from pathlib import Path


def load_report(report_path: str) -> dict:
    """Load verification report JSON."""
    with open(report_path, "r", encoding="utf-8") as f:
        return json.load(f)


def print_report_summary(report: dict, report_path: str):
    """Print report summary."""
    print("\n" + "=" * 60)
    print("📋 VERIFICATION REPORT")
    print("=" * 60)
    print(f"Report: {report_path}")
    print(f"Repository: {report.get('org', '?')}/{report.get('repo', '?')}")
    print(f"PR Number: {report.get('number', '?')}")
    print(f"Valid: {'✅ YES' if report.get('valid', False) else '❌ NO'}")

    if report.get("error_msg"):
        print(f"Error: {report['error_msg']}")

    test = report.get("test_patch_result", {})
    fix = report.get("fix_patch_result", {})

    print("\n📊 Test Results:")
    print(f"  Test Patch (original): {test.get('passed', 0)} passed")
    print(f"  Fix Patch (AI):        {fix.get('passed', 0)} passed")

    # Show comparison
    comparison = report.get("comparison", {})
    test_passed = comparison.get("test_passed", 0)
    fix_passed = comparison.get("fix_passed", 0)
    diff = fix_passed - test_passed

    print(f"\n🔍 Comparison:")
    if diff > 0:
        print(f"  ✅ AI fix-patch passed {diff} MORE tests")
    elif diff == 0:
        print(f"  ✓  AI fix-patch passed SAME tests")
    else:
        print(f"  ❌ AI fix-patch passed {abs(diff)} FEWER tests")

    print(f"\n  Message: {report.get('message', '')}")

    print("=" * 60 + "\n")


def check_directory(directory: str) -> list:
    """Find all report.json files in directory."""
    reports = []
    for root, dirs, files in os.walk(directory):
        if "report.json" in files:
            reports.append(os.path.join(root, "report.json"))
    return reports


def main():
    parser = argparse.ArgumentParser(
        description="Check AI fix-patch verification report"
    )
    parser.add_argument(
        "report_path",
        type=str,
        nargs="?",
        help="Path to report.json file"
    )
    parser.add_argument(
        "--dir",
        type=str,
        help="Directory to search for report.json files"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    args = parser.parse_args()

    if not args.report_path and not args.dir:
        parser.print_help()
        sys.exit(1)

    if args.dir:
        # Find all reports in directory
        reports = check_directory(args.dir)
        if not reports:
            print(f"No report.json files found in {args.dir}")
            sys.exit(0)

        print(f"Found {len(reports)} report(s) in {args.dir}\n")

        valid_count = 0
        invalid_count = 0

        for report_path in reports:
            try:
                report = load_report(report_path)
                if args.json:
                    print(json.dumps({"path": report_path, "valid": report.get("valid", False)}))
                else:
                    status = "✅" if report.get("valid", False) else "❌"
                    comparison = report.get("comparison", {})
                    test_passed = comparison.get("test_passed", 0)
                    fix_passed = comparison.get("fix_passed", 0)

                    if report.get("valid", False):
                        valid_count += 1
                    else:
                        invalid_count += 1

                    diff = fix_passed - test_passed
                    if diff > 0:
                        diff_str = f"+{diff}"
                    else:
                        diff_str = str(diff)

                    print(f"{status} {report_path}")
                    print(f"   {report.get('org', '?')}/{report.get('repo', '?')}#{report.get('number', '?')} - test:{test_passed} → fix:{fix_passed} ({diff_str})")
            except Exception as e:
                print(f"❌ Error loading {report_path}: {e}")

        print("\n" + "=" * 60)
        print(f"Summary: {valid_count} valid, {invalid_count} invalid")
        print("=" * 60)

    else:
        # Single report
        try:
            report = load_report(args.report_path)
            if args.json:
                print(json.dumps(report, indent=2))
            else:
                print_report_summary(report, args.report_path)
        except Exception as e:
            print(f"❌ Error loading report: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
