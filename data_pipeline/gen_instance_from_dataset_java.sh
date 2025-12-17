#!/usr/bin/env bash
set -euo pipefail

RAW_JSON="$1"
EXTRA_JSON="$2"   # 新增参数

if [ ! -f "$RAW_JSON" ]; then
    echo "❌ raw dataset not found: $RAW_JSON"
    exit 1
fi

if [ ! -f "$EXTRA_JSON" ]; then
    echo "❌ extra JSON not found: $EXTRA_JSON"
    exit 1
fi

###################################################
# Extract fields (org/repo/lang)
###################################################
LINE=$(head -n 1 "$RAW_JSON")

ORG=$(echo "$LINE" | sed -n 's/.*"org": *"\([^"]*\)".*/\1/p')
REPO=$(echo "$LINE" | sed -n 's/.*"repo": *"\([^"]*\)".*/\1/p')
LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')

if [ -z "$LANG_RAW" ]; then
    LANG_RAW="java"
fi

LANG=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')

########################################
# Build setup_commands block
########################################
ESCAPED_SETUP=$(jq -r '.setup_commands | join("\n")' "$EXTRA_JSON" | sed 's|[/&]|\\&|g')
ESCAPED_SETUP=${ESCAPED_SETUP//$'\n'/\\n}

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
BASE_DIR="./multi_swe_bench/harness/repos/$LANG_DIR/$ORG_PY"
mkdir -p "$BASE_DIR"

TARGET_FILE="$BASE_DIR/${REPO_PY}.py"

echo "📄 Generating instance file:"
echo "   $TARGET_FILE"

###################################################
# Golang enhanced template (通用模板)
###################################################
cat > "$TARGET_FILE" << 'EOF'
import re
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
        return "ubuntu:22.04"

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

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
WORKDIR /home/
RUN apt-get update && apt-get install -y git openjdk-11-jdk
RUN apt-get install -y maven
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

    def image_tag(self) -> str:
        return f"pr-{self.pr.number}"

    def workdir(self) -> str:
        return f"pr-{self.pr.number}"

    def files(self) -> list[File]:
        return [
            File(".", "fix.patch", f"{self.pr.fix_patch}"),
            File(".", "test.patch", f"{self.pr.test_patch}"),
            File(".", "run.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
./mvnw clean test -fae
""".format(pr=self.pr)),
            File(".", "test-run.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
git apply /home/test.patch
./mvnw clean test -fae
""".format(pr=self.pr)),
            File(".", "fix-run.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
git apply /home/test.patch /home/fix.patch
./mvnw clean test -fae
""".format(pr=self.pr)),
            File(".", "check_git_changes.sh", """#!/bin/bash
set -e
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Not inside git repo"; exit 1;
fi
if [[ -n $(git status --porcelain) ]]; then
  echo "Uncommitted changes"; exit 1;
fi
echo "Clean"
"""),
            File(".", "resolve_go_file.sh", """#!/bin/bash
set -e
REPO_PATH="$1"
find "$REPO_PATH" -type f -name "*.go" | while read -r file; do
  if [[ $(cat "$file") =~ ^[./a-zA-Z0-9_\\-]+\\.go$ ]]; then
    target=$(cat "$file")
    abs=$(realpath -m "$(dirname "$file")/$target")
    if [ -f "$abs" ]; then
      cat "$abs" > "$file"
    fi
  fi
done
"""),
            File(".", "prepare.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
git reset --hard
bash /home/check_git_changes.sh
git checkout {pr.base.sha}
bash /home/check_git_changes.sh

# Injected setup commands
__SETUP_COMMANDS_BLOCK__

cd /home/{pr.repo}
./mvnw clean test -fae
""".format(pr=self.pr)),
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

    def parse_log(self, test_log: str) -> TestResult:
        passed, failed, skipped = set(), set(), set()

        re_pass = re.compile(r"--- PASS: (\\S+)")
        re_fail = re.compile(r"--- FAIL: (\\S+)")
        re_skip = re.compile(r"--- SKIP: (\\S+)")

        for line in test_log.splitlines():
            line = line.strip()
            if m := re_pass.match(line): passed.add(m.group(1))
            if m := re_fail.match(line): failed.add(m.group(1))
            if m := re_skip.match(line): skipped.add(m.group(1))

        return TestResult(
            passed_count=len(passed),
            failed_count=len(failed),
            skipped_count=len(skipped),
            passed_tests=passed,
            failed_tests=failed,
            skipped_tests=skipped,
        )
EOF

########################################
# Replace placeholder with commands
########################################
# macOS + Linux compatible sed
sed -i "" "s|__SETUP_COMMANDS_BLOCK__|$ESCAPED_SETUP|g" "$TARGET_FILE" 2>/dev/null \
    || sed -i "s|__SETUP_COMMANDS_BLOCK__|$ESCAPED_SETUP|g" "$TARGET_FILE"

echo "✅ Injected setup commands from $EXTRA_JSON"
###################################################
# Inject org/repo into template
###################################################
# Replace placeholder {{ORG}} {{REPO}}
sed -i "" "s/{{ORG}}/$ORG/g"  "$TARGET_FILE" 2>/dev/null || sed -i "s/{{ORG}}/$ORG/g" "$TARGET_FILE"
sed -i "" "s/{{REPO}}/$REPO/g" "$TARGET_FILE" 2>/dev/null || sed -i "s/{{REPO}}/$REPO/g" "$TARGET_FILE"

echo "✅ Generated: $TARGET_FILE"