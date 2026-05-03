#!/usr/bin/env python3
"""Build one base image at a time, verify matched patches, then clean up."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from multi_swe_bench.harness import repos  # noqa: F401
from multi_swe_bench.harness.build_dataset import CliArgs
from multi_swe_bench.harness.image import Config
from multi_swe_bench.harness.instance import Instance
from multi_swe_bench.harness.pull_request import PullRequest


def image_exists(name: str) -> bool:
    result = subprocess.run(
        ["docker", "image", "inspect", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, cwd=cwd, text=True)


def load_raw_prs(raw_dataset: Path) -> dict[tuple[str, str, int], PullRequest]:
    prs = {}
    for line in raw_dataset.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        pr = PullRequest.from_json(line)
        prs[(pr.org, pr.repo, pr.number)] = pr
    return prs


def final_output_image_dir(project_root: Path, stem: str) -> Path:
    direct = project_root / "final_output" / stem / "image"
    if direct.exists():
        return direct

    # Some duplicate dataset variants are named repo-pr_1/repo-pr_2 while
    # final_output keeps the shared image directory at repo-pr.
    if "_" in stem:
        fallback = project_root / "final_output" / stem.rsplit("_", 1)[0] / "image"
        if fallback.exists():
            return fallback
    return direct


def build_base_image(project_root: Path, raw_dataset: Path, pr: PullRequest) -> tuple[str, bool]:
    config = Config(need_clone=True, global_env=None, clear_env=True)
    instance = Instance.create(pr, config)
    base = instance.dependency().dependency()
    base_name = base.image_full_name()
    if image_exists(base_name):
        print(f"Base image already exists: {base_name}", flush=True)
        return base_name, False

    cli = CliArgs(
        mode="image",
        workdir=project_root / "data" / "workdir",
        raw_dataset_files=[str(raw_dataset)],
        force_build=False,
        output_dir=None,
        specifics={pr.id},
        skips=None,
        repo_dir=project_root / "data" / "repos",
        need_clone=True,
        global_env=None,
        clear_env=True,
        stop_on_error=True,
        max_workers=1,
        max_workers_build_image=1,
        max_workers_run_instance=1,
        run_cmd="",
        test_patch_run_cmd="",
        fix_patch_run_cmd="",
        log_dir=project_root / "data" / "logs",
        log_level="INFO",
        log_to_console=True,
        parse_log=True,
        run_log=True,
        human_mode=True,
        agent_timeout=1800,
        docker_build_timeout=7200,
        docker_build_retries=1,
    )
    cli.build_image(base)
    return base_name, True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dataset", type=Path, required=True)
    parser.add_argument("--datasets-dir", type=Path, default=Path("verify_patch/datasets"))
    parser.add_argument("--patches-dir", type=Path, default=Path("verify_patch/matched_patches"))
    parser.add_argument("--reports-dir", type=Path, default=Path("verify_patches/reports"))
    parser.add_argument("--passed-dir", type=Path, default=Path("verify_patches/passed"))
    parser.add_argument("--repo", help="Optional org/repo filter, e.g. gofiber/fiber")
    parser.add_argument("--skip-repo", action="append", default=[], help="Repo to skip, e.g. django/django. Can be repeated.")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--keep-base", action="store_true")
    parser.add_argument("--rerun-passed", action="store_true")
    args = parser.parse_args()

    project_root = Path.cwd()
    raw_prs = load_raw_prs(args.raw_dataset)
    grouped: dict[tuple[str, str], list[tuple[str, Path, Path, PullRequest]]] = defaultdict(list)

    for dataset_path in sorted(args.datasets_dir.glob("*.json")):
        dataset = json.loads(dataset_path.read_text(encoding="utf-8"))
        key = (dataset["org"], dataset["repo"], int(dataset["number"]))
        pr = raw_prs.get(key)
        if pr is None:
            print(f"SKIP missing raw PR: {dataset_path.name}", flush=True)
            continue
        repo_name = f"{pr.org}/{pr.repo}"
        if args.repo and args.repo != repo_name:
            continue
        if repo_name in set(args.skip_repo):
            continue
        patch_path = args.patches_dir / f"{dataset_path.stem}.diff"
        if not patch_path.exists():
            print(f"SKIP missing patch: {patch_path}", flush=True)
            continue
        if not args.rerun_passed and (args.passed_dir / patch_path.name).exists():
            print(f"SKIP already passed: {patch_path.name}", flush=True)
            continue
        grouped[(pr.org, pr.repo)].append((dataset_path.stem, dataset_path, patch_path, pr))

    args.reports_dir.mkdir(parents=True, exist_ok=True)
    args.passed_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    passed = 0
    failed = 0

    for (org, repo), items in sorted(grouped.items()):
        if args.limit and processed >= args.limit:
            break
        print(f"\n=== {org}/{repo}: {len(items)} patch(es) ===", flush=True)
        try:
            base_name, built_for_run = build_base_image(project_root, args.raw_dataset, items[0][3])
        except Exception as exc:
            print(f"FAIL build base for {org}/{repo}: {exc}", flush=True)
            failed += len(items)
            continue

        try:
            for stem, dataset_path, patch_path, _pr in items:
                if args.limit and processed >= args.limit:
                    break
                image_dir = final_output_image_dir(project_root, stem)
                if not (image_dir / "run.sh").exists():
                    print(f"FAIL missing image scripts: {stem}", flush=True)
                    failed += 1
                    processed += 1
                    continue

                report_dir = args.reports_dir / stem
                cmd = [
                    sys.executable,
                    "scripts/verify_ai_fix_patch.py",
                    "--dataset-json",
                    str(dataset_path),
                    "--fix-patch",
                    str(patch_path),
                    "--output-dir",
                    str(report_dir),
                    "--instance-dir",
                    str(image_dir),
                    "--image-name",
                    base_name,
                    "--run-prepare",
                ]
                result = run(cmd, project_root)
                processed += 1
                if result.returncode == 0:
                    shutil.copy2(patch_path, args.passed_dir / patch_path.name)
                    passed += 1
                    print(f"PASS copied: {patch_path.name}", flush=True)
                else:
                    failed += 1
                    print(f"FAIL verify: {stem}", flush=True)
        finally:
            if not args.keep_base and built_for_run:
                subprocess.run(["docker", "rmi", base_name], check=False)
                subprocess.run(["docker", "builder", "prune", "-f"], check=False)

    print(json.dumps({"processed": processed, "passed": passed, "failed": failed}, indent=2))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
