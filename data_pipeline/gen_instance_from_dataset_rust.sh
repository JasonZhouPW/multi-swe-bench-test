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

ORG=$(echo "$LINE" | sed -n 's/.*"org": *"\([^"]*\)".*/\1/p')
REPO=$(echo "$LINE" | sed -n 's/.*"repo": *"\([^"]*\)".*/\1/p')
LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')

if [ -z "$LANG_RAW" ]; then
    LANG_RAW="rust"
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

###################################################
# Create folder
###################################################
BASE_DIR="$PROJ_ROOT/multi_swe_bench/harness/repos/$LANG_DIR/$ORG_PY"
mkdir -p "$BASE_DIR"

TARGET_FILE="$BASE_DIR/${REPO_PY}.py"

echo "📄 Generating instance file:"
echo "   $TARGET_FILE"

###################################################
# Rust enhanced template (generic template)
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
        return "rust:latest"

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
set -e

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "check_git_changes: Not inside a git repository"
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "check_git_changes: Uncommitted changes"
  exit 1
fi

echo "check_git_changes: No uncommitted changes"
exit 0

""".format(),
            ),
            File(
                ".",
                "prepare.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
git reset --hard
bash /home/check_git_changes.sh
git checkout {pr.base.sha}
bash /home/check_git_changes.sh

# Injected setup commands
__SETUP_COMMANDS_BLOCK__

cargo test || true

""".format(pr=self.pr),
            ),
            File(
                ".",
                "run.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
cargo test

""".format(pr=self.pr),
            ),
            File(
                ".",
                "test-run.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
git apply /home/test.patch
cargo test

""".format(pr=self.pr),
            ),
            File(
                ".",
                "fix-run.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
git apply /home/test.patch /home/fix.patch
cargo test

""".format(pr=self.pr),
            ),
        ]

    def dockerfile(self) -> str:
        image = self.dependency()
        name = image.image_name()
        tag = image.image_tag()

        copy_commands = ""
        for file in self.files():
            copy_commands += f"COPY {file.name} /home/\n"

        prepare_commands = "RUN bash /home/prepare.sh"

        return f"""FROM {name}:{tag}

{self.global_env}

{copy_commands}

{prepare_commands}

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

    def parse_log(self, test_log: str) -> TestResult:
        passed_tests = set()
        failed_tests = set()
        skipped_tests = set()

        re_pass_tests = [re.compile(r"test (\S+) ... ok")]
        re_fail_tests = [re.compile(r"test (\S+) ... FAILED")]
        re_skip_tests = [re.compile(r"test (\S+) ... ignored")]

        for line in test_log.splitlines():
            line = line.strip()

            for re_pass in re_pass_tests:
                match = re_pass.match(line)
                if match:
                    passed_tests.add(match.group(1))

            for re_fail in re_fail_tests:
                match = re_fail.match(line)
                if match:
                    failed_tests.add(match.group(1))

            for re_skip in re_skip_tests:
                match = re_skip.match(line)
                if match:
                    skipped_tests.add(match.group(1))

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
# Replace placeholder {{ORG}} {{REPO}}
sed -i "" "s/{{ORG}}/$ORG/g"  "$TARGET_FILE" 2>/dev/null || sed -i "s/{{ORG}}/$ORG/g" "$TARGET_FILE"
sed -i "" "s/{{REPO}}/$REPO/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/{{REPO}}/$REPO/g" "$TARGET_FILE"

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