#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the project root
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RAW_JSON="$1"
EXTRA_JSON="${2:-}"   # optional parameter

if [ ! -f "$RAW_JSON" ]; then
    echo "❌ raw dataset not found: $RAW_JSON"
    exit 1
fi

# Check if the dataset file is empty
if [ ! -s "$RAW_JSON" ]; then
    echo "⚠️  raw dataset is empty, skipping: $RAW_JSON"
    exit 0
fi

# if [ ! -f "$EXTRA_JSON" ]; then
#     echo "❌ extra JSON not found: $EXTRA_JSON"
#     exit 1
# fi

###################################################
# Extract fields
###################################################
LINE=$(head -n 1 "$RAW_JSON")

ORG=$(echo "$LINE" | jq -r '.org')
REPO=$(echo "$LINE" | jq -r '.repo')
# Prefer base_commit_hash over base.sha for more reliable SHA extraction
BASE_SHA=$(echo "$LINE" | jq -r '.base_commit_hash // .base.sha // empty')
LANG_RAW=$(echo "$LINE" | jq -r '.language // "typescript"')

if [ -z "$LANG_RAW" ]; then
    LANG_RAW="typescript"
fi


LANG=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')

########################################
# Build setup_commands block
########################################
if [ -n "$EXTRA_JSON" ] && [ -f "$EXTRA_JSON" ]; then
    SETUP_COMMANDS=$(jq -r '(.setup_commands // []) | join("\n")' "$EXTRA_JSON")
else
    SETUP_COMMANDS=""
fi
export SETUP_COMMANDS

###################################################
# Map language → folder
###################################################
case "$LANG" in
    go|golang)
        LANG_DIR="golang"
        ;;
    python|py)
        LANG_DIR="python"
        ;;
    javascript|js|node|nodejs)
        LANG_DIR="javascript"
        ;;
    rust)
        LANG_DIR="rust"
        ;;
    java)
        LANG_DIR="java"
        ;;
    cpp|c++|c)
        LANG_DIR="cpp"
        ;;
    typescript|TypeScript|ts)
        LANG_DIR="typescript"
        ;;
    *)
        echo "❌ Unsupported language: $LANG"
        exit 1
        ;;
esac

###################################################
# Normalize package names
###################################################
ORG_PY=$(echo "$ORG" | tr '-' '_' | tr 'A-Z' 'a-z')
REPO_PY=$(echo "$REPO" | tr '-' '_' | tr 'A-Z' 'a-z')

CLASS_NAME=$(echo "$REPO_PY" | sed -E 's/(^|_)([a-z])/\U\2/g')

repo_name="$REPO"
pr_base_sha="$BASE_SHA"

###################################################
# Create folder
###################################################
BASE_DIR="$PROJ_ROOT/multi_swe_bench/harness/repos/$LANG_DIR/$ORG_PY"
mkdir -p "$BASE_DIR"

TARGET_FILE="$BASE_DIR/${REPO_PY}.py"

echo "📄 Generating instance file:"
echo "   $TARGET_FILE"

###################################################
# TypeScript enhanced template (generic template)
###################################################
cat > "$TARGET_FILE" << 'EOF'
import re
import json
from typing import Optional, Union

from multi_swe_bench.harness.image import Config, File, Image
from multi_swe_bench.harness.instance import Instance, TestResult
from multi_swe_bench.harness.pull_request import PullRequest


class ImageBase(Image):
    def __init__(self, pr: PullRequest, config: Config):
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    @property
    def config(self) -> Config:
        return self._config

    def dependency(self) -> Union[str, "Image"]:
        return "node:20"

    def image_tag(self) -> str:
        return "base"

    def workdir(self) -> str:
        return "base"

    def files(self) -> list[File]:
        return []

    def dockerfile(self) -> str:
        image_name = self.dependency()
        if isinstance(image_name, Image):
            image_name = image_name.image_full_name()

        if self.config.need_clone:
            # Use timeout to avoid hanging on network issues (full clone, no --depth)
            code = f"RUN apt-get update && apt-get install -y git && (timeout 600 git clone https://github.com/{self.pr.org}/{self.pr.repo}.git /home/{self.pr.repo} || (echo 'Git clone failed or timed out' && exit 1))"
        else:
            code = f"COPY {self.pr.repo} /home/{self.pr.repo}"

        return f"""FROM {image_name}

{self.global_env}

WORKDIR /home/

{code}

{self.clear_env}

"""


class ImageDefault(Image):
    def __init__(self, pr: PullRequest, config: Config):
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    @property
    def config(self) -> Config:
        return self._config

    def dependency(self) -> Image | None:
        return ImageBase(self.pr, self.config)

    def image_prefix(self) -> str:
        return "envagent"

    def image_tag(self) -> str:
        return f"pr-{self.pr.number}"

    def workdir(self) -> str:
        return f"pr-{self.pr.number}"

    def files(self) -> list[File]:
        repo_name = self.pr.repo
        return [
            File(
                ".",
                "fix.patch",
                f"{self.pr.fix_patch}",
            ),
            File(
                ".",
                "test.patch",
                f"{self.pr.test_patch}",
            ),
            File(
                ".",
                "check_git_changes.sh",
                """#!/bin/bash
# Check if there are any uncommitted changes in the git repository
if git status --porcelain | grep -q .; then
    echo "Error: There are uncommitted changes in the repository."
    git status
    exit 1
else
    echo "Git repository is clean."
fi""",
            ),
            File(
                ".",
                "prepare.sh",
                """#!/bin/bash
set -e

cd /home/[[REPO_NAME]]
echo "Starting prepare.sh"
git reset --hard
echo "Git reset done"
bash /home/check_git_changes.sh
echo "First git check done"
git checkout {pr.base_commit_hash}
echo "Git checkout done"
bash /home/check_git_changes.sh
echo "Second git check done"

# Injected setup commands
# Check for Python backend with poetry
if [ -f backend/poetry.lock ]; then
    echo "Installing poetry for Python backend..."
    apt-get update && apt-get install -y python3-pip
    pip3 install --break-system-packages poetry || python3 -m pip install --break-system-packages poetry || true
    echo "Poetry installed"
    cd /home/[[REPO_NAME]]/backend
    poetry install || python3 -m poetry install || true
    echo "Poetry install done"
    cd /home/[[REPO_NAME]]
fi

# Check for bazel/Bazelisk (Angular uses bazel for testing)
if [ -f "BUILD.bazel" ] || [ -d "bazel" ] || grep -q "bazelisk" package.json 2>/dev/null; then
    echo "Installing bazelisk for bazel testing..."
    apt-get update && apt-get install -y wget
    wget -O /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-arm64
    chmod +x /usr/local/bin/bazelisk
    ln -sf /usr/local/bin/bazelisk /usr/local/bin/bazel
    echo "Bazelisk installed"
fi


if [ -f package.json ] && grep -q '"packageManager"' package.json && grep -q 'pnpm' package.json; then
    echo "Using pnpm"
    npm install -g pnpm@latest-10 || true
    echo "Pnpm installed"
    pnpm install --strict-peer-dependencies=false || true
    echo "Pnpm install done"
    pnpm add eslint --save-dev -w --strict-peer-dependencies=false || true
    echo "Eslint added with pnpm"
elif [ -f package.json ] && grep -q '"packageManager"' package.json && grep -q 'yarn' package.json; then
    echo "Using yarn"
    npm install -g yarn || true
    echo "Yarn installed"
    yarn install || true
    echo "Yarn install done"
elif [ -f yarn.lock ]; then
    echo "Using yarn (found yarn.lock)"
    npm install -g yarn || true
    echo "Yarn installed"
    yarn install || yarn || true
    echo "Yarn install done"
else
    echo "Using npm"
    npm ci --legacy-peer-deps || true
    echo "Npm ci done"
fi
echo "Prepare.sh completed successfully"
""".format(pr=self.pr),
            ),
            File(
                ".",
                "run.sh",
                """#!/bin/bash
cd /home/[[REPO_NAME]]
# Angular uses bazel for testing
if [ -f "BUILD.bazel" ] || [ -d "bazel" ] || grep -q "bazelisk" package.json 2>/dev/null; then
    bazelisk test //packages/... //tools/... //modules/... 2>&1 || true
elif [ -f backend/poetry.lock ]; then
    export PATH="$HOME/.local/bin:$PATH"
    cd backend && (poetry run pytest || python3 -m poetry run pytest)
elif [ -f yarn.lock ] || grep -q '"packageManager"' package.json 2>/dev/null && grep -q 'yarn' package.json 2>/dev/null; then
    CI=true yarn test:app || CI=true yarn test || CI=true yarn run test || true
else
    npm test
fi

""",
            ),
            File(
                ".",
                "test-run.sh",
                """#!/bin/bash
cd /home/[[REPO_NAME]]
# Apply test.patch only if it exists and is not empty
if [ -s /home/test.patch ]; then
    git apply --exclude package.json --whitespace=nowarn /home/test.patch || echo "Warning: git apply test.patch failed"
else
    echo "No test.patch to apply (empty or missing)"
fi
# Angular uses bazel for testing
if [ -f "BUILD.bazel" ] || [ -d "bazel" ] || grep -q "bazelisk" package.json 2>/dev/null; then
    bazelisk test //packages/... //tools/... //modules/... 2>&1 || true
elif [ -f backend/poetry.lock ]; then
    export PATH="$HOME/.local/bin:$PATH"
    cd backend && (poetry run pytest || python3 -m poetry run pytest)
elif [ -f yarn.lock ] || grep -q '"packageManager"' package.json 2>/dev/null && grep -q 'yarn' package.json 2>/dev/null; then
    CI=true yarn test:app || CI=true yarn test || CI=true yarn run test || true
else
    npm test
fi

""",
            ),
            File(
                ".",
                "fix-run.sh",
                """#!/bin/bash
set -e

cd /home/[[REPO_NAME]]
# Apply patches: test.patch (if exists) and fix.patch
if [ -s /home/test.patch ]; then
    git apply --exclude package.json --whitespace=nowarn /home/test.patch /home/fix.patch || git apply --exclude package.json --whitespace=nowarn /home/fix.patch
else
    # No test.patch, only apply fix.patch
    git apply --exclude package.json --whitespace=nowarn /home/fix.patch
fi
# Angular uses bazel for testing
if [ -f "BUILD.bazel" ] || [ -d "bazel" ] || grep -q "bazelisk" package.json 2>/dev/null; then
    bazelisk test //packages/... //tools/... //modules/... 2>&1 || true
elif [ -f backend/poetry.lock ]; then
    export PATH="$HOME/.local/bin:$PATH"
    cd backend && (poetry run pytest || python3 -m poetry run pytest)
elif [ -f yarn.lock ] || grep -q '"packageManager"' package.json 2>/dev/null && grep -q 'yarn' package.json 2>/dev/null; then
    CI=true yarn test:app || CI=true yarn test || CI=true yarn run test || true
else
    npm test
fi

""",
            ),
        ]

    def dockerfile(self) -> str:
        parent = self.dependency()
        name = parent.image_name()
        tag = parent.image_tag()

        copy_cmds = "".join([f"COPY {f.name} /home/\n" for f in self.files()])

        return f"""FROM {name}:{tag}

{self.global_env}

{copy_cmds}

RUN bash /home/prepare.sh

{self.clear_env}

"""


@Instance.register("{{ORG}}", "{{REPO}}")
class InstanceTemplate(Instance):
    def __init__(self, pr: PullRequest, config: Config, *args, **kwargs):
        super().__init__()
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    def dependency(self) -> Optional[Image]:
        return ImageDefault(self.pr, self._config)

    def run(self, cmd: str = "") -> str:
        return cmd or "bash /home/run.sh"

    def test_patch_run(self, cmd: str = "") -> str:
        return cmd or "bash /home/test-run.sh"

    def fix_patch_run(self, cmd: str = "") -> str:
        return cmd or "bash /home/fix-run.sh"

    def parse_log(self, log: str) -> TestResult:
        passed_tests = set()
        failed_tests = set()
        skipped_tests = set()
        import re

        # Track test names - failed takes precedence over passed
        test_status = {}

        # Bazel format: "//target:name   PASSED" or "FAILED"
        bazel_pattern = re.compile(r"^//(.+?)\s+(PASSED|FAILED|TIMEOUT)", re.MULTILINE)
        for match in bazel_pattern.finditer(log):
            target = match.group(1).strip()
            status = match.group(2).strip().lower()
            test_status[target] = status

        # Bazel summary: "3 tests passed, 1 failed"
        bazel_summary = re.compile(r"(\d+)\s+tests?\s+passed.*?(\d+)\s+tests?\s+failed", re.MULTILINE)
        for match in bazel_summary.finditer(log):
            if not test_status:
                num_passed = int(match.group(1))
                num_failed = int(match.group(2))
                for i in range(num_passed):
                    test_status[f"bazel_test_{i}"] = 'passed'
                for i in range(num_failed):
                    test_status[f"bazel_failed_{i}"] = 'failed'

        # Bazel "Executed X tests" format
        bazel_executed = re.compile(r"Executed\s+(\d+)\s+tests?", re.MULTILINE)
        for match in bazel_executed.finditer(log):
            if not test_status:
                num_tests = int(match.group(1))
                for i in range(num_tests):
                    test_status[f"bazel_test_{i}"] = 'passed'

        # Pytest format: "test_file.py::test_function PASSED/FAILED/SKIPPED"
        pytest_pattern = re.compile(
            r"^(\S+\.py::\S+)\s+(PASSED|FAILED|SKIPPED)", re.MULTILINE
        )

        for match in pytest_pattern.finditer(log):
            test_name = match.group(1).strip()
            status = match.group(2).strip().lower()
            test_status[test_name] = status

        # Pytest short summary: "2 passed, 1 failed"
        pytest_summary_pattern = re.compile(
            r"(\d+)\s+passed.*?(\d+)\s+failed", re.MULTILINE
        )
        for match in pytest_summary_pattern.finditer(log):
            # If we found a summary but no individual tests, use generic names
            if not test_status:
                num_passed = int(match.group(1))
                num_failed = int(match.group(2))
                for i in range(num_passed):
                    test_status[f"test_{i}"] = 'passed'
                for i in range(num_failed):
                    test_status[f"failed_test_{i}"] = 'failed'

        # Failed tests first (✖)
        failed_pattern = re.compile(
            r"^\s*✖\s+(.+?)(?:\s+\(\d+(?:\.\d+)?\s*ms\))?$", re.MULTILINE
        )

        for match in failed_pattern.finditer(log):
            test_name = match.group(1).strip()
            test_status[test_name] = 'failed'

        # Vitest format: "✓ filename.test.ts (X tests) XXms"
        vitest_pattern = re.compile(
            r".*[✓✔]\s+([a-zA-Z_/-]+\.test\.(ts|js))\s+\(\d+\s*tests?\)\s+\d+\.?\d*ms"
        )

        for match in vitest_pattern.finditer(log):
            test_file = match.group(1).strip()
            if test_file not in test_status:
                test_status[test_file] = 'passed'

        # Standard test framework format (✓ or ✔ test name [XXms])
        # Handle both checkmark characters and optional timing
        standard_pattern = re.compile(
            r"^\s*[✓✔]\s+(.+?)(?:\s+\(\d+(?:\.\d+)?\s*ms\))?$", re.MULTILINE
        )

        for match in standard_pattern.finditer(log):
            test_name = match.group(1).strip()
            if test_name not in test_status:
                test_status[test_name] = 'passed'

        # Separate into passed and failed sets
        for test_name, status in test_status.items():
            if status == 'passed':
                passed_tests.add(test_name)
            elif status == 'failed':
                failed_tests.add(test_name)
            else:
                skipped_tests.add(test_name)

        return TestResult(
            passed_count=len(passed_tests),
            failed_count=len(failed_tests),
            skipped_count=len(skipped_tests),
            passed_tests=passed_tests,
            failed_tests=failed_tests,
            skipped_tests=skipped_tests,
        )
EOF

########################################
# Replace placeholder with commands
########################################
# macOS + Linux compatible sed
perl -0777 -i.bak -pe '
    s/__SETUP_COMMANDS_BLOCK__/$ENV{SETUP_COMMANDS}/g
' "$TARGET_FILE"

echo "✅ Injected setup commands from $EXTRA_JSON"
###################################################
# Inject org/repo into template
###################################################
# Replace placeholder {{ORG}} {{REPO}} [[REPO_NAME]]
sed -i "" "s/{{ORG}}/$ORG/g"  "$TARGET_FILE" 2>/dev/null || sed -i "s/{{ORG}}/$ORG/g" "$TARGET_FILE"
sed -i "" "s/{{REPO}}/$REPO/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/{{REPO}}/$REPO/g" "$TARGET_FILE"
sed -i "" "s/\[\[REPO_NAME\]\]/$repo_name/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/\[\[REPO_NAME\]\]/$repo_name/g" "$TARGET_FILE"

rm -f "$TARGET_FILE.bak"

echo "✅ Generated: $TARGET_FILE"

# Create __init__.py
INIT_FILE="$BASE_DIR/__init__.py"
> "$INIT_FILE"
for pyfile in "$BASE_DIR"/*.py; do
    filename=$(basename "$pyfile" .py)
    if [ "$filename" != "__init__" ]; then
        # Skip files with dots in the name (e.g., reveal.js.py) - use underscore version instead
        if [[ "$filename" == *"."* ]]; then
            # Convert reveal.js.py to reveal_js
            filename="${filename//./_}"
        fi
        echo "from multi_swe_bench.harness.repos.$LANG_DIR.$ORG_PY.$filename import *" >> "$INIT_FILE"
    fi
done
echo "✅ Generated: $INIT_FILE"

# Rebuild language root __init__.py from all org/__init__.py files
LANG_INIT="$BASE_DIR/../__init__.py"
> "$LANG_INIT"
for org_dir in "$BASE_DIR"/../*/; do
    if [ -f "$org_dir/__init__.py" ]; then
        cat "$org_dir/__init__.py" >> "$LANG_INIT"
        echo "" >> "$LANG_INIT"
    fi
done
echo "✅ Generated: $LANG_INIT"

# Add language import to repos/__init__.py if not already present
REPOS_INIT="$PROJ_ROOT/multi_swe_bench/harness/repos/__init__.py"
mkdir -p "$(dirname "$REPOS_INIT")"
if [ ! -f "$REPOS_INIT" ]; then
    echo "# Auto-generated by gen scripts" > "$REPOS_INIT"
    echo "" >> "$REPOS_INIT"
fi
if ! grep -q "repos\.$LANG_DIR import" "$REPOS_INIT"; then
    echo "from multi_swe_bench.harness.repos.$LANG_DIR import *" >> "$REPOS_INIT"
    echo "✅ Added import to repos/__init__.py"
fi