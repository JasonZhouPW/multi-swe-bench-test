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
BASE_SHA=$(echo "$LINE" | jq -r '.base.sha')
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
            code = f"RUN git clone https://github.com/{self.pr.org}/{self.pr.repo}.git /home/{self.pr.repo}"
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
git checkout [[BASE_SHA]]
echo "Git checkout done"
bash /home/check_git_changes.sh
echo "Second git check done"

# Injected setup commands


if [ -f package.json ] && grep -q '"packageManager"' package.json && grep -q 'pnpm' package.json; then
    echo "Using pnpm"
    npm install -g pnpm@latest-10 || true
    echo "Pnpm installed"
    pnpm install || true
    echo "Pnpm install done"
    pnpm add eslint --save-dev -w || true
    echo "Eslint added with pnpm"
else
    echo "Using npm"
    npm ci || true
    echo "Npm ci done"
    npm install eslint --save-dev
    echo "Eslint added with npm"
fi
echo "Prepare.sh completed successfully"
""",
            ),
            File(
                ".",
                "run.sh",
                """#!/bin/bash
cd /home/[[REPO_NAME]]
npm test

""",
            ),
            File(
                ".",
                "test-run.sh",
                """#!/bin/bash
cd /home/[[REPO_NAME]]
git apply  --exclude package.json --whitespace=nowarn /home/test.patch
npm test

""",
            ),
            File(
                ".",
                "fix-run.sh",
                """#!/bin/bash
set -e

cd /home/[[REPO_NAME]]
git apply  --exclude package.json --whitespace=nowarn /home/test.patch /home/fix.patch
npm test

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

        # Failed tests first (✖)
        failed_pattern = re.compile(
            r"^\s*✖\s+(.+?)(?:\s*\(\d+(?:\.\d+)?\s*ms\))?$", re.MULTILINE
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

        # Standard test framework format (✔ test name XXms)
        standard_pattern = re.compile(
            r"^\s*✔\s+(.+?)(?:\s*\(\d+(?:\.\d+)?\s*ms\))?$", re.MULTILINE
        )

        for match in standard_pattern.finditer(log):
            test_name = match.group(1).strip()
            if test_name not in test_status:
                test_status[test_name] = 'passed'

        # Separate into passed and failed sets
        for test_name, status in test_status.items():
            if status == 'passed':
                passed_tests.add(test_name)
            else:
                failed_tests.add(test_name)

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
# Replace placeholder {{ORG}} {{REPO}} [[REPO_NAME]] [[BASE_SHA]]
sed -i "" "s/{{ORG}}/$ORG/g"  "$TARGET_FILE" 2>/dev/null || sed -i "s/{{ORG}}/$ORG/g" "$TARGET_FILE"
sed -i "" "s/{{REPO}}/$REPO/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/{{REPO}}/$REPO/g" "$TARGET_FILE"
sed -i "" "s/\[\[REPO_NAME\]\]/$repo_name/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/\[\[REPO_NAME\]\]/$repo_name/g" "$TARGET_FILE"
sed -i "" "s/\[\[BASE_SHA\]\]/$pr_base_sha/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/\[\[BASE_SHA\]\]/$pr_base_sha/g" "$TARGET_FILE"

rm -f "$TARGET_FILE.bak"

echo "✅ Generated: $TARGET_FILE"

# Create __init__.py
INIT_FILE="$BASE_DIR/__init__.py"
> "$INIT_FILE"
for pyfile in "$BASE_DIR"/*.py; do
    filename=$(basename "$pyfile" .py)
    if [ "$filename" != "__init__" ]; then
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