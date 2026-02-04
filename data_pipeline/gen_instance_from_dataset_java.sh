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
# Change LANG to lowercase




########################################
# Build setup_commands block
########################################
# ESCAPED_SETUP=$(jq -r '.setup_commands | join("\n")' "$EXTRA_JSON" | sed 's|[/&]|\\&|g')
# ESCAPED_SETUP=${ESCAPED_SETUP//$'\n'/\\n}
if [ -n "$EXTRA_JSON" ] && [ -f "$EXTRA_JSON" ]; then
    # Use empty array fallback to avoid errors when the field is missing
    ESCAPED_SETUP=$(jq -r '(.setup_commands // []) | join("\n")' "$EXTRA_JSON" | sed 's|[/&]|\\&|g')
    # Replace literal newlines with \n so the Python triple-quoted string preserves newlines when interpreted
    ESCAPED_SETUP=${ESCAPED_SETUP//$'\n'/\\n}
else
    ESCAPED_SETUP=""
fi

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
# replace REPO_PY "." to "_" for filename safety
REPO_PY=$(echo "$REPO_PY" | tr '.' '_')
TARGET_FILE="$BASE_DIR/${REPO_PY}.py"


echo "📄 Generating instance file:"
echo "   $TARGET_FILE"

###################################################
# Java enhanced template (generic template)
###################################################
cat > "$TARGET_FILE" << 'EOF'
import os
import re
import xml.etree.ElementTree as ET
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

    def get_java_version(self) -> str:
        repo_path = f"./data/repos/{self.pr.org}/{self.pr.repo}"
        if not os.path.exists(repo_path):
            return "17"  # default
        pom_path = os.path.join(repo_path, "pom.xml")
        if os.path.exists(pom_path):
            try:
                tree = ET.parse(pom_path)
                root = tree.getroot()
                # find properties/java.version
                for prop in root.findall(".//properties/java.version"):
                    version = prop.text
                    if version.startswith("1."):
                        version = version[2:]  # 1.8 -> 8
                    return version
            except:
                pass
        gradle_path = os.path.join(repo_path, "build.gradle")
        gradle_kts_path = os.path.join(repo_path, "build.gradle.kts")
        for gradle_file in [gradle_path, gradle_kts_path]:
            if os.path.exists(gradle_file):
                with open(gradle_file, 'r') as f:
                    content = f.read()
                    # find sourceCompatibility = '17' or "17"
                    match = re.search(r'sourceCompatibility\s*=\s*[\'"]([^\'"]+)[\'"]', content)
                    if match:
                        version = match.group(1)
                        if version.startswith("1."):
                            version = version[2:]
                        return version
                    # also check javaVersion
                    match = re.search(r'javaVersion\s*=\s*[\'"]([^\'"]+)[\'"]', content)
                    if match:
                        version = match.group(1)
                        if version.startswith("1."):
                            version = version[2:]
                        return version
                    # check jvmTarget for Kotlin
                    match = re.search(r'jvmTarget\s*=\s*[\'"]([^\'"]+)[\'"]', content)
                    if match:
                        version = match.group(1)
                        if version.startswith("1."):
                            version = version[2:]
                        return version
                    # check languageVersion for Gradle toolchain
                    match = re.search(r'languageVersion\s*=\s*JavaLanguageVersion\.of\((\d+)\)', content)
                    if match:
                        version = match.group(1)
                        return version
        return "17"  # default

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

        java_version = self.get_java_version()

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
RUN apt-get update && apt-get install -y git openjdk-{java_version}-jdk
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

    def get_java_version(self) -> str:
        repo_path = f"./data/repos/{self.pr.org}/{self.pr.repo}"
        if not os.path.exists(repo_path):
            return "17"  # default
        pom_path = os.path.join(repo_path, "pom.xml")
        if os.path.exists(pom_path):
            try:
                tree = ET.parse(pom_path)
                root = tree.getroot()
                # find properties/java.version
                for prop in root.findall(".//properties/java.version"):
                    version = prop.text
                    if version.startswith("1."):
                        version = version[2:]  # 1.8 -> 8
                    return version
            except:
                pass
        gradle_path = os.path.join(repo_path, "build.gradle")
        gradle_kts_path = os.path.join(repo_path, "build.gradle.kts")
        for gradle_file in [gradle_path, gradle_kts_path]:
            if os.path.exists(gradle_file):
                with open(gradle_file, 'r') as f:
                    content = f.read()
                    # find sourceCompatibility = '17' or "17"
                    match = re.search(r'sourceCompatibility\s*=\s*[\'"]([^\'"]+)[\'"]', content)
                    if match:
                        version = match.group(1)
                        if version.startswith("1."):
                            version = version[2:]
                        return version
                    # also check javaVersion
                    match = re.search(r'javaVersion\s*=\s*[\'"]([^\'"]+)[\'"]', content)
                    if match:
                        version = match.group(1)
                        if version.startswith("1."):
                            version = version[2:]
                        return version
                    # check jvmTarget for Kotlin
                    match = re.search(r'jvmTarget\s*=\s*[\'"]([^\'"]+)[\'"]', content)
                    if match:
                        version = match.group(1)
                        if version.startswith("1."):
                            version = version[2:]
                        return version
                    # check languageVersion for Gradle toolchain
                    match = re.search(r'languageVersion\s*=\s*JavaLanguageVersion\.of\((\d+)\)', content)
                    if match:
                        version = match.group(1)
                        return version
        return "17"  # default

    def image_tag(self) -> str:
        return f"pr-{self.pr.number}"

    def workdir(self) -> str:
        return f"pr-{self.pr.number}"

    def files(self) -> list[File]:
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
  git status
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

# Check if Maven pom.xml exists, otherwise use Gradle
if [ -f "pom.xml" ]; then
    mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false --batch-mode || true
else
    ./gradlew test --info --continue || true
fi
""".format(pr=self.pr),
            ),
            File(
                ".",
                "run.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
if [ -f "pom.xml" ]; then
    mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false --batch-mode
else
    ./gradlew test --info
fi
""".format(pr=self.pr),
            ),
            File(
                ".",
                "test-run.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
echo "DEBUG: git status before apply:"
git status
echo "DEBUG: applying patch verbose:"
git apply --verbose --whitespace=nowarn /home/test.patch || {{
    echo "APPLY FAILED"
    echo "DEBUG: File content around line 30:"
    head -n 50 gson/src/test/java/com/google/gson/functional/DefaultTypeAdaptersTest.java
    exit 1
}}
if [ -f "pom.xml" ]; then
    mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false --batch-mode
else
    ./gradlew test --info
fi

""".format(pr=self.pr),
            ),
            File(
                ".",
                "fix-run.sh",
                """#!/bin/bash
set -e

cd /home/{pr.repo}
git apply --whitespace=nowarn /home/test.patch /home/fix.patch
if [ -f "pom.xml" ]; then
    mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false --batch-mode
else
    ./gradlew test --info
fi

""".format(pr=self.pr),
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

    def parse_log(self, test_log: str) -> TestResult:
        import re as _re

        passed_tests = set()
        failed_tests = set()
        skipped_tests = set()

        # Remove ANSI color codes
        ansi_escape = _re.compile(r'\x1b\[[0-9;]*m')
        clean_log = ansi_escape.sub('', test_log)

        # Parse individual test results (Gradle format)
        # Look for lines like: "TestClass > testMethod PASSED"
        test_result_pattern = _re.compile(r'^(.+?)\s*>\s*(.+?)\s+(PASSED|FAILED|SKIPPED)$', _re.MULTILINE)
        matches = test_result_pattern.findall(clean_log)

        for class_name, method_name, status in matches:
            test_name = f"{class_name}.{method_name}"
            if status == "PASSED":
                passed_tests.add(test_name)
            elif status == "FAILED":
                failed_tests.add(test_name)
            elif status == "SKIPPED":
                skipped_tests.add(test_name)

        # If no individual test results found, try to parse summary (fallback)
        if not (passed_tests or failed_tests or skipped_tests):
            # Try Maven Surefire format as fallback
            re_pass_tests = [
                _re.compile(
                    r"\[INFO\]\s+Running\s+(.+?)\s*\n.*?INFO.*?Tests run:\s*(\d+),\s*Failures:\s*(\d+),\s*Errors:\s*(\d+),\s*Skipped:\s*(\d+),\s*Time elapsed:\s*[\d.]+\s*s"
                )
            ]

            for re_pass_test in re_pass_tests:
                tests = re_pass_test.findall(clean_log, _re.MULTILINE | _re.DOTALL)
                for test in tests:
                    test_name = test[0]
                    tests_run = int(test[1])
                    failures = int(test[2])
                    errors = int(test[3])
                    skipped = int(test[4])
                    if (
                        tests_run > 0
                        and failures == 0
                        and errors == 0
                        and skipped != tests_run
                    ):
                        passed_tests.add(test_name)
                    elif failures > 0 or errors > 0:
                        failed_tests.add(test_name)
                    elif skipped == tests_run:
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