#!/usr/bin/env python3
"""
Verify AI-generated fix-patch effectiveness.

This script validates whether an AI-generated fix patch actually fixes the reported issue
by running the test patch with and without the fix patch in a Docker container.

Usage:
    python scripts/verify_ai_fix_patch.py \
        --dataset-json /path/to/<org>_<repo>-<pr_number>_dataset.json \
        --output-dir /path/to/output/directory \
        [--mode image|docker]

Example:
    # Use existing image directory (faster)
    python scripts/verify_ai_fix_patch.py \
        --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
        --output-dir verify_output/ \
        --mode image

    # Use Docker to run tests
    python scripts/verify_ai_fix_patch.py \
        --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
        --output-dir verify_output/ \
        --mode docker
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))


def load_dataset_json(json_path: str) -> dict:
    """Load dataset JSON file."""
    with open(json_path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_patch_to_file(patch_content: str, output_path: str) -> bool:
    """Write patch content to a temp file."""
    try:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(patch_content)
        return True
    except Exception as e:
        print(f"Error writing patch file: {e}")
        return False


def prepare_patches(dataset: dict, output_dir: str) -> tuple[bool, str, str]:
    """
    Prepare test.patch and fix.patch files in the output directory.

    Returns:
        (success, test_patch_path, fix_patch_path)
    """
    test_patch = dataset.get("test_patch", "")
    fix_patch = dataset.get("fix_patch", "")

    if not fix_patch:
        print("⚠️  Warning: fix_patch is empty in dataset JSON")
    if not test_patch:
        print("⚠️  Warning: test_patch is empty in dataset JSON")

    test_patch_path = os.path.join(output_dir, "test.patch")
    fix_patch_path = os.path.join(output_dir, "fix.patch")

    success = True
    if test_patch:
        if not write_patch_to_file(test_patch, test_patch_path):
            success = False
        else:
            print(f"✅ Wrote test.patch to {test_patch_path}")
    else:
        write_patch_to_file("", test_patch_path)

    if fix_patch:
        if not write_patch_to_file(fix_patch, fix_patch_path):
            success = False
        else:
            print(f"✅ Wrote fix.patch to {fix_patch_path}")

    return success, test_patch_path, fix_patch_path


def get_image_name(dataset: dict) -> str:
    """Generate Docker image name from dataset."""
    org = dataset.get("org", "").lower().replace("/", "_")
    repo = dataset.get("repo", "").lower().replace("/", "_")
    pr_number = dataset.get("number", 0)
    return f"mswebench/{org}_m_{repo}:pr-{pr_number}"


def run_docker_command(
    image_name: str,
    command: str,
    volumes: dict = None,
    workdir: str = "/home",
) -> str:
    """Run a command in Docker container and return output."""
    docker_cmd = ["docker", "run", "--rm"]

    if volumes:
        for host_path, container_path in volumes.items():
            docker_cmd.extend(["-v", f"{host_path}:{container_path}"])

    docker_cmd.extend([
        "-w", workdir,
        image_name,
        "bash", "-c", command
    ])

    try:
        result = subprocess.run(
            docker_cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minutes timeout
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return "Error: Command timed out (10 minutes)"
    except Exception as e:
        return f"Error: {e}"


def run_test_in_docker(
    image_name: str,
    instance_dir: str,
    output_dir: str,
    test_patch_path: str,
    fix_patch_path: str,
    stage: str = "run",
    run_prepare: bool = False,
) -> str:
    """
    Run test stage in Docker.

    Args:
        image_name: Docker image to use
        instance_dir: Directory containing run.sh, test-run.sh, fix-run.sh
        output_dir: Directory to store logs
        stage: One of "run", "test", "fix"
    """
    script_map = {
        "run": "run.sh",
        "test": "test-run.sh",
        "fix": "fix-run.sh",
    }

    script = script_map.get(stage)
    if not script:
        return f"Error: Unknown stage {stage}"

    script_path = os.path.join(instance_dir, script)
    if not os.path.exists(script_path):
        return f"Error: Script not found: {script_path}"

    # Run the script in Docker. Mount scripts individually under /home so the
    # repository directory baked into the base image remains visible.
    volumes = {
        output_dir: "/home/output",
        test_patch_path: "/home/test.patch",
        fix_patch_path: "/home/fix.patch",
    }
    for name in [
        "run.sh",
        "test-run.sh",
        "fix-run.sh",
        "prepare.sh",
        "check_git_changes.sh",
        "resolve_go_file.sh",
    ]:
        host_path = os.path.join(instance_dir, name)
        if os.path.exists(host_path):
            volumes[host_path] = f"/home/{name}"

    prepare_cmd = "bash /home/prepare.sh && " if run_prepare and os.path.exists(os.path.join(instance_dir, "prepare.sh")) else ""
    command = f"cd /home && {prepare_cmd}bash /home/{script} 2>&1 | tee /home/output/{stage}-run.log"

    print(f"🔧 Running stage '{stage}' in Docker...")
    output = run_docker_command(image_name, command, volumes)

    return output


def parse_test_log(log_content: str) -> dict:
    """
    Parse test log to extract test results.

    Returns dict with passed, failed, skipped counts and test details.
    """
    result = {
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "tests": {}
    }

    # Match pytest output patterns
    passed_pattern = r"([^\s]+)::([^\s]+)\s+PASSED"
    failed_pattern = r"([^\s]+)::([^\s]+)\s+FAILED"
    skipped_pattern = r"([^\s]+)::([^\s]+)\s+SKIPPED"

    for line in log_content.split("\n"):
        # Check for PASSED
        match = re.search(passed_pattern, line)
        if match:
            test_name = f"{match.group(1)}::{match.group(2)}"
            result["passed"] += 1
            result["tests"][test_name] = "PASS"
            continue

        # Check for FAILED
        match = re.search(failed_pattern, line)
        if match:
            test_name = f"{match.group(1)}::{match.group(2)}"
            result["failed"] += 1
            result["tests"][test_name] = "FAIL"
            continue

        # Check for SKIPPED
        match = re.search(skipped_pattern, line)
        if match:
            test_name = f"{match.group(1)}::{match.group(2)}"
            result["skipped"] += 1
            result["tests"][test_name] = "SKIP"
            continue

    return result


def generate_verification_report(
    dataset: dict,
    run_result: dict,
    test_result: dict,
    fix_result: dict,
    output_dir: str,
) -> dict:
    """
    Generate verification report.

    Validation logic:
    - Run test_patch only → get test_passed count
    - Run test_patch + fix_patch → get fix_passed count
    - valid = (fix_passed >= test_passed)
    """
    report = {
        "org": dataset.get("org"),
        "repo": dataset.get("repo"),
        "number": dataset.get("number"),
        "run_result": run_result,
        "test_patch_result": test_result,
        "fix_patch_result": fix_result,
        "valid": True,
        "error_msg": "",
        "comparison": {
            "test_passed": test_result.get("passed", 0),
            "fix_passed": fix_result.get("passed", 0),
        }
    }

    # Core validation: fix_passed >= test_passed
    test_passed = test_result.get("passed", 0)
    fix_passed = fix_result.get("passed", 0)

    if fix_passed >= test_passed:
        report["valid"] = True
        report["error_msg"] = ""
        if fix_passed > test_passed:
            report["message"] = f"Fix patch passed {fix_passed - test_passed} more tests than original"
        else:
            report["message"] = "Fix patch passed same number of tests as original"
    else:
        report["valid"] = False
        report["error_msg"] = f"Invalid: fix_patch passed ({fix_passed}) < test_patch passed ({test_passed})"
        report["message"] = f"Fix patch passed {test_passed - fix_passed} fewer tests than original"

    # Write report
    report_path = os.path.join(output_dir, "report.json")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    return report


def print_verification_summary(report: dict):
    """Print verification summary."""
    print("\n" + "=" * 60)
    print("📋 VERIFICATION SUMMARY")
    print("=" * 60)
    print(f"Repository: {report['org']}/{report['repo']}")
    print(f"PR Number: {report['number']}")
    print(f"Valid: {'✅ YES' if report['valid'] else '❌ NO'}")

    if report.get("error_msg"):
        print(f"Error: {report['error_msg']}")

    test = report.get("test_patch_result", {})
    fix = report.get("fix_patch_result", {})

    print("\n📊 Test Results:")
    print(f"  Test Patch (original): {test.get('passed', 0)} passed, {test.get('failed', 0)} failed, {test.get('skipped', 0)} skipped")
    print(f"  Fix Patch (AI):        {fix.get('passed', 0)} passed, {fix.get('failed', 0)} failed, {fix.get('skipped', 0)} skipped")

    # Show comparison
    comparison = report.get("comparison", {})
    test_passed = comparison.get("test_passed", 0)
    fix_passed = comparison.get("fix_passed", 0)
    diff = fix_passed - test_passed

    print(f"\n🔍 Comparison:")
    if diff > 0:
        print(f"  ✅ AI fix-patch passed {diff} MORE tests than original")
    elif diff == 0:
        print(f"  ✓  AI fix-patch passed SAME number of tests as original")
    else:
        print(f"  ❌ AI fix-patch passed {abs(diff)} FEWER tests than original")

    print(f"\n  Message: {report.get('message', '')}")

    print("=" * 60 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Verify AI-generated fix-patch effectiveness"
    )
    parser.add_argument(
        "--dataset-json",
        type=str,
        required=True,
        help="Path to the dataset JSON file"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        required=True,
        help="Path to the output directory for logs and reports"
    )
    parser.add_argument(
        "--image-name",
        type=str,
        default=None,
        help="Docker image name to use (auto-generated if not provided)"
    )
    parser.add_argument(
        "--instance-dir",
        type=str,
        default=None,
        help="Path to instance directory (for run.sh, test-run.sh, fix-run.sh scripts)"
    )
    parser.add_argument(
        "--fix-patch",
        type=str,
        default=None,
        help="Path to fix-patch file (overrides fix_patch in dataset JSON)"
    )
    parser.add_argument(
        "--test-patch",
        type=str,
        default=None,
        help="Path to test-patch file (overrides test_patch in dataset JSON)"
    )
    parser.add_argument(
        "--run-prepare",
        action="store_true",
        help="Run prepare.sh before each test stage. Useful when verifying against a base image instead of a PR image."
    )

    args = parser.parse_args()

    print("=" * 60)
    print("🔍 AI Fix-Patch Verification")
    print("=" * 60)
    print(f"Dataset JSON: {args.dataset_json}")
    print(f"Output Dir:   {args.output_dir}")
    print(f"Image Name:   {args.image_name or '(auto)'}")
    if args.fix_patch:
        print(f"Fix Patch:  {args.fix_patch} (external file)")
    if args.test_patch:
        print(f"Test Patch: {args.test_patch} (external file)")
    if args.run_prepare:
        print("Run Prepare: enabled")
    print("=" * 60 + "\n")

    # Load dataset
    print("📂 Loading dataset JSON...")
    try:
        dataset = load_dataset_json(args.dataset_json)
        print(f"✅ Loaded dataset for {dataset.get('org', '?')}/{dataset.get('repo', '?')}#{dataset.get('number', '?')}")
    except Exception as e:
        print(f"❌ Failed to load dataset JSON: {e}")
        sys.exit(1)

    # Override patches from external files if provided
    if args.fix_patch:
        print(f"📝 Loading fix-patch from external file: {args.fix_patch}")
        with open(args.fix_patch, "r", encoding="utf-8") as f:
            dataset["fix_patch"] = f.read()
    if args.test_patch:
        print(f"📝 Loading test-patch from external file: {args.test_patch}")
        with open(args.test_patch, "r", encoding="utf-8") as f:
            dataset["test_patch"] = f.read()

    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)

    # Prepare patches
    print("\n📝 Preparing patches...")
    success, test_patch_path, fix_patch_path = prepare_patches(dataset, args.output_dir)
    if not success:
        print("❌ Failed to prepare patches")
        sys.exit(1)

    # Get image name
    image_name = args.image_name or get_image_name(dataset)
    print(f"\n🐳 Using Docker image: {image_name}")

    # Determine instance directory
    instance_dir = args.instance_dir
    if not instance_dir:
        # Try to find instance directory relative to dataset JSON
        dataset_dir = os.path.dirname(os.path.abspath(args.dataset_json))
        candidate_dirs = [
            os.path.join(dataset_dir, "image"),
            os.path.join(dataset_dir, "instance"),
            dataset_dir,
        ]
        for candidate in candidate_dirs:
            if os.path.exists(os.path.join(candidate, "run.sh")):
                instance_dir = candidate
                break

    if not instance_dir or not os.path.exists(os.path.join(instance_dir, "run.sh")):
        print("⚠️  No instance directory found with run.sh, test-run.sh, fix-run.sh")
        print("   Please provide --instance-dir pointing to the directory with these scripts")
        sys.exit(1)

    print(f"📁 Using instance directory: {instance_dir}")

    # Run tests in Docker
    print("\n" + "=" * 60)
    print("🏃 Running Tests")
    print("=" * 60)

    print("\n1️⃣  Running base test (no patches)...")
    run_log = run_test_in_docker(
        image_name, instance_dir, args.output_dir, test_patch_path, fix_patch_path, "run", args.run_prepare
    )
    with open(os.path.join(args.output_dir, "run.log"), "w") as f:
        f.write(run_log)
    run_result = parse_test_log(run_log)
    print(f"   Result: {run_result['passed']} passed, {run_result['failed']} failed, {run_result['skipped']} skipped")

    print("\n2️⃣  Running test with test patch...")
    test_log = run_test_in_docker(
        image_name, instance_dir, args.output_dir, test_patch_path, fix_patch_path, "test", args.run_prepare
    )
    with open(os.path.join(args.output_dir, "test-patch-run.log"), "w") as f:
        f.write(test_log)
    test_result = parse_test_log(test_log)
    print(f"   Result: {test_result['passed']} passed, {test_result['failed']} failed, {test_result['skipped']} skipped")

    print("\n3️⃣  Running test with fix patch...")
    fix_log = run_test_in_docker(
        image_name, instance_dir, args.output_dir, test_patch_path, fix_patch_path, "fix", args.run_prepare
    )
    with open(os.path.join(args.output_dir, "fix-patch-run.log"), "w") as f:
        f.write(fix_log)
    fix_result = parse_test_log(fix_log)
    print(f"   Result: {fix_result['passed']} passed, {fix_result['failed']} failed, {fix_result['skipped']} skipped")

    # Generate report
    print("\n📊 Generating verification report...")
    report = generate_verification_report(
        dataset,
        run_result,
        test_result,
        fix_result,
        args.output_dir,
    )

    print_verification_summary(report)

    print("=" * 60)
    print("✅ Verification completed!")
    print(f"Output directory: {args.output_dir}")
    print(f"Report file: {os.path.join(args.output_dir, 'report.json')}")
    print("=" * 60)

    # Exit with error if verification failed
    if not report["valid"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
