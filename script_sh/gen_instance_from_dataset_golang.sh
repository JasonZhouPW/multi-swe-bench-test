#!/usr/bin/env bash
set -euo pipefail

RAW_JSON="$1"

if [ ! -f "$RAW_JSON" ]; then
    echo "❌ raw dataset not found: $RAW_JSON"
    exit 1
fi

###################################################
# Extract fields
###################################################
LINE=$(head -n 1 "$RAW_JSON")

ORG=$(echo "$LINE" | sed -n 's/.*"org": *"\([^"]*\)".*/\1/p')
REPO=$(echo "$LINE" | sed -n 's/.*"repo": *"\([^"]*\)".*/\1/p')
LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')

if [ -z "$LANG_RAW" ]; then
    LANG_RAW="golang"
fi

LANG=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')

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

CLASS_NAME=$(echo "$REPO_PY" | sed -E 's/(^|_)([a-z])/\U\2/g')   # snake → CamelCase

###################################################
# Create folder
###################################################
BASE_DIR="./multi_swe_bench/harness/repos/$LANG_DIR/$ORG_PY"
mkdir -p "$BASE_DIR"

TARGET_FILE="$BASE_DIR/${REPO_PY}.py"

echo "📄 Generating instance file:"
echo "   $TARGET_FILE"

###################################################
# Write the template with variable replacements
###################################################
cat > "$TARGET_FILE" <<EOF
# Auto-generated instance for $ORG/$REPO

import re
from typing import Optional, Union

from multi_swe_bench.harness.image import Config, File, Image
from multi_swe_bench.harness.instance import Instance, TestResult
from multi_swe_bench.harness.pull_request import PullRequest


class ${CLASS_NAME}ImageBase(Image):
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
        return "golang:latest"

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


class ${CLASS_NAME}ImageDefault(Image):
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
        return ${CLASS_NAME}ImageBase(self.pr, self.config)

    def image_tag(self) -> str:
        return f"pr-{self.pr.number}"

    def workdir(self) -> str:
        return f"pr-{self.pr.number}"

    def files(self) -> list[File]:
        return [
            File(".", "fix.patch", f"{self.pr.fix_patch}"),
            File(".", "test.patch", f"{self.pr.test_patch}"),
        ]

    def dockerfile(self) -> str:
        parent = self.dependency()
        name = parent.image_name()
        tag = parent.image_tag()

        copy_commands = ""
        for file in self.files():
            copy_commands += f"COPY {file.name} /home/\n"

        return f"""FROM {name}:{tag}

{self.global_env}

{copy_commands}

RUN bash /home/prepare.sh

{self.clear_env}

"""


@Instance.register("${ORG}", "${REPO}")
class ${CLASS_NAME}(Instance):
    def __init__(self, pr: PullRequest, config: Config, *args, **kwargs):
        super().__init__()
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    def dependency(self) -> Optional[Image]:
        return ${CLASS_NAME}ImageDefault(self.pr, self._config)

    def run(self, cmd: str = "") -> str:
        return cmd or "bash /home/run.sh"

    def test_patch_run(self, cmd: str = "") -> str:
        return cmd or "bash /home/test-run.sh"

    def fix_patch_run(self, cmd: str = "") -> str:
        return cmd or "bash /home/fix-run.sh"

    def parse_log(self, test_log: str) -> TestResult:
        passed = set()
        failed = set()
        skipped = set()

        re_pass = re.compile(r"--- PASS: (\S+)")
        re_fail = re.compile(r"--- FAIL: (\S+)")
        re_skip = re.compile(r"--- SKIP: (\S+)")

        for line in test_log.splitlines():
            line = line.strip()

            m = re_pass.match(line)
            if m: passed.add(m.group(1))

            m = re_fail.match(line)
            if m: failed.add(m.group(1))

            m = re_skip.match(line)
            if m: skipped.add(m.group(1))

        return TestResult(
            passed_count=len(passed),
            failed_count=len(failed),
            skipped_count=len(skipped),
            passed_tests=passed,
            failed_tests=failed,
            skipped_tests=skipped,
        )
EOF

echo "✅ Generated: $TARGET_FILE"