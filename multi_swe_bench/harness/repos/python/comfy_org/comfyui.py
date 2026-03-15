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
        return "python:3.11-slim"

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
                "prepare.sh",
                """#!/bin/bash
set -e

cd /home/[[REPO_NAME]]
echo "Starting prepare.sh"

# Install git first since it may not be available in base image
if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y git || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git || true
    elif command -v apk >/dev/null 2>&1; then
        apk add git || true
    fi
fi

git reset --hard
bash /home/check_git_changes.sh
echo "Git reset done"

git checkout {self.pr.base_commit_hash}
bash /home/check_git_changes.sh
echo "Git checkout done"

# Injected setup commands

# Install system dependencies if apt-get is available
if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y gcc g++ make libpq-dev python3-dev || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y gcc gcc-c++ make postgresql-devel || true
fi
###ACTION_DELIMITER###
pip install --upgrade pip setuptools wheel || true
###ACTION_DELIMITER###
if [ -f requirements.txt ]; then
    pip install -r requirements.txt || true
fi
###ACTION_DELIMITER###
pip install -e . || true
###ACTION_DELIMITER###
pip install pytest coverage colorama || true
###ACTION_DELIMITER###
echo 'coverage run -m pytest -v --tb=short --basetemp=/tmp tests/' > test_commands.sh
###ACTION_DELIMITER###

cat test_commands.sh
###ACTION_DELIMITER###
bash test_commands.sh || true""".replace("[[REPO_NAME]]", repo_name),
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
                "run.sh",
                """#!/bin/bash
cd /home/[[REPO_NAME]]
coverage run -m pytest -v --tb=short --basetemp=/tmp tests/

""".replace("[[REPO_NAME]]", repo_name),
            ),
            File(
                ".",
                "test-run.sh",
                """#!/bin/bash
set -e

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y git || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git || true
    elif command -v apk >/dev/null 2>&1; then
        apk add git || true
    fi
fi

cd /home/[[REPO_NAME]]
# Apply test.patch only if it exists and is not empty
if [ -s /home/test.patch ]; then
    if ! git apply --whitespace=nowarn /home/test.patch 2>/dev/null; then
        echo "Warning: git apply test.patch failed, trying alternative method..."
        exit 1
    fi
else
    echo "No test.patch to apply (empty or missing)"
fi
coverage run -m pytest -v --tb=short --basetemp=/tmp tests/

""".replace("[[REPO_NAME]]", repo_name),
            ),
            File(
                ".",
                "fix-run.sh",
                """#!/bin/bash
set -e

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y git || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git || true
    elif command -v apk >/dev/null 2>&1; then
        apk add git || true
    fi
fi

cd /home/[[REPO_NAME]]
# Apply patches: test.patch (if exists) and fix.patch
if [ -s /home/test.patch ]; then
    if ! git apply --whitespace=nowarn /home/test.patch /home/fix.patch 2>/dev/null; then
        echo "Warning: git apply both patches failed, trying fix.patch only..."
        if ! git apply --whitespace=nowarn /home/fix.patch 2>/dev/null; then
            echo "Warning: git apply fix.patch also failed"
            exit 1
        fi
    fi
else
    # No test.patch, only apply fix.patch
    if ! git apply --whitespace=nowarn /home/fix.patch 2>/dev/null; then
        echo "Warning: git apply fix.patch failed"
        exit 1
    fi
fi
coverage run -m pytest -v --tb=short --basetemp=/tmp tests/

""".replace("[[REPO_NAME]]", repo_name),
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


@Instance.register("Comfy-Org", "ComfyUI")
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
        # Parse the log content and extract test execution results.
        passed_tests = set()  # Tests that passed successfully
        failed_tests = set()  # Tests that failed
        skipped_tests = set()  # Tests that were skipped
        import re

        # Regex patterns to match test cases
        pattern1 = re.compile(
            r"(tests/[^:]+::[^ ]+)\s+(PASSED|FAILED|SKIPPED|XFAIL)\b"
        )  # Capture full test name (non-whitespace) after ::
        # Find all matches for pattern1
        for match in pattern1.finditer(log):
            test_name = match.group(1)
            status = match.group(2)
            if status == "PASSED":
                passed_tests.add(test_name)
            elif status == "FAILED":
                failed_tests.add(test_name)
            elif status == "SKIPPED":
                skipped_tests.add(test_name)
            elif status == "XFAIL":
                failed_tests.add(test_name)  # XFAIL is considered a failure

        # Handle pytest ERROR cases (e.g., import errors during collection)
        # Format: "ERROR tests/test_module.py"
        error_pattern = re.compile(r"^ERROR\s+(tests/[^:]+::[^ ]+)\b", re.MULTILINE)
        for match in error_pattern.finditer(log):
            test_name = match.group(1)
            failed_tests.add(test_name)

        # Also capture "ERROR tests/test_module.py" without the test name
        error_file_pattern = re.compile(r"^ERROR\s+(tests/[^.]+\.py)\b", re.MULTILINE)
        for match in error_file_pattern.finditer(log):
            test_file = match.group(1)
            failed_tests.add(test_file)

        parsed_results = {
            "passed_tests": passed_tests,
            "failed_tests": failed_tests,
            "skipped_tests": skipped_tests,
        }

        return TestResult(
            passed_count=len(passed_tests),
            failed_count=len(failed_tests),
            skipped_count=len(skipped_tests),
            passed_tests=passed_tests,
            failed_tests=failed_tests,
            skipped_tests=skipped_tests,
        )
