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

ORG=$(echo "$LINE" | sed -n 's/.*"org": *"\([^"]*\)".*/\1/p')
REPO=$(echo "$LINE" | sed -n 's/.*"repo": *"\([^"]*\)".*/\1/p')
LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')

# Prefer base_commit_hash over base.sha for more reliable SHA extraction
PR_BASE_SHA=$(echo "$LINE" | sed -n 's/.*"base_commit_hash": *"\([^"]*\)".*/\1/p')
if [ -z "$PR_BASE_SHA" ]; then
    # Fallback to base.sha if base_commit_hash is not available
    PR_BASE_SHA=$(echo "$LINE" | sed -n 's/.*"base":[^}]*"sha": *"\([^"]*\)".*/\1/p')
fi

if [ -z "$LANG_RAW" ]; then
    LANG_RAW="python"
fi

LANG=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')

########################################
# Detect test directory (test or tests)
########################################
# Clone repo temporarily to detect test directory structure
TEMP_REPO_DIR="$PROJ_ROOT/data/temp_detect/$ORG/$REPO"
mkdir -p "$TEMP_REPO_DIR"
rm -rf "$TEMP_REPO_DIR"/*

# Try to fetch the repository - try multiple common default branch names
# Skip clone if network is slow - we have fallback logic
cd "$TEMP_REPO_DIR"
CLONE_SUCCESS=false

# Git clone with timeout and retry logic
# Uses perl alarm for timeout (60 seconds per attempt)
git_clone_with_timeout() {
    local retry_count=3
    local attempt=1
    while [ $attempt -le $retry_count ]; do
        echo "🔄 Git clone attempt $attempt/$retry_count for https://github.com/$ORG/$REPO.git"
        if perl -e 'alarm shift; exit(system(@ARGV) >> 8)' 60 git clone "$@" 2>/dev/null; then
            echo "✅ Git clone successful on attempt $attempt"
            return 0
        fi
        echo "⚠️  Attempt $attempt failed, retrying in 2 seconds..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "❌ Git clone failed after $retry_count attempts"
    return 1
}

# Try clone with timeout and retry (use perl with system instead of exec for proper exit code)
for branch in master main devel; do
    if git_clone_with_timeout --branch "$branch" https://github.com/$ORG/$REPO.git .; then
        CLONE_SUCCESS=true
        break
    fi
done

# If no branch worked, try without specifying branch
if [ "$CLONE_SUCCESS" = "false" ]; then
    if git_clone_with_timeout https://github.com/$ORG/$REPO.git .; then
        CLONE_SUCCESS=true
    fi
fi

if [ "$CLONE_SUCCESS" = "true" ]; then
    # Check which test directory exists
    if [ -d "test" ] && [ ! -d "tests" ]; then
        TEST_DIR="test"
        echo "📁 Detected test directory: test"
    elif [ -d "tests" ] && [ ! -d "test" ]; then
        TEST_DIR="tests"
        echo "📁 Detected test directory: tests"
    elif [ -d "tests" ]; then
        # Both exist, prefer tests
        TEST_DIR="tests"
        echo "📁 Detected test directory: tests (both exist)"
    elif [ -d "test" ]; then
        TEST_DIR="test"
        echo "📁 Detected test directory: test (only)"
    else
        TEST_DIR="tests"
        echo "⚠️  No test directory found, defaulting to tests"
    fi

    # Check for e2e and runtime subdirectories
    IGNORE_E2E=""
    IGNORE_RUNTIME=""
    if [ -d "$TEST_DIR/e2e" ]; then
        IGNORE_E2E="--ignore=$TEST_DIR/e2e"
    fi
    if [ -d "$TEST_DIR/runtime" ]; then
        IGNORE_RUNTIME="--ignore=$TEST_DIR/runtime"
    fi

    # Special handling for ansible - use test/units instead of full test/
    # Ansible's test/integration/ contains Ansible modules that execute main() on import
    # causing argparse conflicts when pytest collects them
    if [ "$REPO" = "ansible" ]; then
        TEST_DIR="test/units"
        IGNORE_E2E="--ignore=test/integration"
        IGNORE_RUNTIME="--ignore=test/support"
        echo "📁 Ansible detected: using $TEST_DIR for pytest to avoid integration test collection errors"
    fi

    # Special handling for ragflow - use test/unit_test instead of full test/
    # ragflow's test/testcases requires environment variables like ZHIPU_AI_API_KEY
    if [ "$REPO" = "ragflow" ]; then
        TEST_DIR="test/unit_test"
        IGNORE_E2E=""
        IGNORE_RUNTIME=""
        echo "📁 Ragflow detected: using $TEST_DIR for pytest to avoid environment variable requirements"
    fi

    # Special handling for langchain monorepo
    # langchain's tests are in libs/langchain/tests
    if [ "$REPO" = "langchain" ] && [ -d "libs/langchain/tests" ]; then
        TEST_DIR="libs/langchain/tests"
        IGNORE_E2E=""
        IGNORE_RUNTIME=""
        echo "📁 Langchain monorepo detected: using $TEST_DIR"
    fi

    # Special handling for langflow
    # langflow's tests are in src/backend/tests
    if [ "$REPO" = "langflow" ] && [ -d "src/backend/tests" ]; then
        TEST_DIR="src/backend/tests"
        IGNORE_E2E=""
        IGNORE_RUNTIME=""
        echo "📁 Langflow detected: using $TEST_DIR"
    fi
else
    # Default to tests if detection fails
    TEST_DIR="tests"
    IGNORE_E2E="--ignore=$TEST_DIR/e2e"
    IGNORE_RUNTIME="--ignore=$TEST_DIR/runtime"
    echo "⚠️  Failed to clone repo, defaulting to tests"

    # Special handling for known monorepos even when clone fails
    if [ "$REPO" = "langchain" ]; then
        TEST_DIR="libs/langchain/tests"
        IGNORE_E2E=""
        IGNORE_RUNTIME=""
        echo "📁 Langchain monorepo detected: using $TEST_DIR"
    fi

    if [ "$REPO" = "langflow" ]; then
        TEST_DIR="src/backend/tests"
        IGNORE_E2E=""
        IGNORE_RUNTIME=""
        echo "📁 Langflow detected: using $TEST_DIR"
    fi
fi

cd "$PROJ_ROOT" || true
rm -rf "$TEMP_REPO_DIR" || true

export TEST_DIR
export IGNORE_E2E
export IGNORE_RUNTIME

########################################
# Extract Python version from pyproject.toml if available
########################################
PYTHON_VERSION=""
if [ -n "$EXTRA_JSON" ] && [ -f "$EXTRA_JSON" ]; then
    # Try to get python_version from extra JSON first
    PYTHON_VERSION=$(jq -r '.python_version // empty' "$EXTRA_JSON" 2>/dev/null || echo "")
fi

# If not in extra JSON, try to fetch from repo's pyproject.toml
if [ -z "$PYTHON_VERSION" ]; then
    # Fetch pyproject.toml from GitHub and extract requires-python
    PYPROJECT_URL="https://raw.githubusercontent.com/$ORG/$REPO/$PR_BASE_SHA/pyproject.toml"
    PYPROJECT_CONTENT=$(curl -sL --retry 3 --connect-timeout 10 --max-time 30 "$PYPROJECT_URL" 2>/dev/null || echo "")
    if [ -n "$PYPROJECT_CONTENT" ]; then
        # Extract requires-python value (e.g., ">=3.12,<3.14" -> "3.12")
        # Use || true to prevent exit on grep failure with set -e
        REQUIRES_PYTHON=$(echo "$PYPROJECT_CONTENT" | grep -i '^requires-python' | sed -n 's/^requires-python[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
        if [ -n "$REQUIRES_PYTHON" ]; then
            # Extract minimum version from range (e.g., ">=3.12,<3.14" -> "3.12")
            PYTHON_VERSION=$(echo "$REQUIRES_PYTHON" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
        fi
    fi
fi

# Set default if still empty
if [ -z "$PYTHON_VERSION" ]; then
    PYTHON_VERSION="3.11"
fi

echo "🐍 Python version: $PYTHON_VERSION"

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
# Python enhanced template (generic template)
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
        # Use python_version from PR if specified, otherwise default to 3.11
        python_version = self.pr.python_version or "3.11"
        return f"python:{python_version}-slim"

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
            code = f"""RUN apt-get update && apt-get install -y git && (timeout 600 git clone https://github.com/{self.pr.org}/{self.pr.repo}.git /home/{self.pr.repo} || (echo 'Git clone failed or timed out' && exit 1))"""
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
                f"""#!/bin/bash
# Note: Removed set -e to allow script to continue even if commands fail
# This ensures we see what actually fails and don't exit early

cd /home/[[REPO_NAME]]
echo "=== Starting prepare.sh ==="
echo "Current directory: $(pwd)"

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

echo "=== Running git reset ==="
git reset --hard || echo "git reset failed, continuing..."
bash /home/check_git_changes.sh || echo "check_git_changes.sh failed, continuing..."
echo "Git reset done"

echo "=== Running git checkout {pr.base_commit_hash} ==="
git checkout {pr.base_commit_hash} || echo "git checkout failed, continuing..."
bash /home/check_git_changes.sh || echo "check_git_changes.sh failed, continuing..."
echo "Git checkout done"

# Injected setup commands
__SETUP_COMMANDS_BLOCK__

echo "=== Installing system dependencies ==="
# Install system dependencies if apt-get is available
if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y gcc g++ make libpq-dev python3-dev || echo "apt-get install failed"
elif command -v yum >/dev/null 2>&1; then
    yum install -y gcc gcc-c++ make postgresql-devel || echo "yum install failed"
fi
###ACTION_DELIMITER###
echo "=== Upgrading pip ==="
pip install --upgrade pip setuptools wheel || echo "pip upgrade failed"
###ACTION_DELIMITER###
echo "=== Checking for requirements.txt ==="
if [ -f requirements.txt ]; then
    echo "Installing requirements.txt..."
    pip install -r requirements.txt || echo "pip install requirements.txt failed"
else
    echo "No requirements.txt found"
fi
###ACTION_DELIMITER###
echo "=== Installing package in editable mode ==="
pip install -e . || echo "pip install -e . failed"
###ACTION_DELIMITER###
echo "=== Installing test dependencies ==="
pip install pytest pytest-mock coverage colorama syrupy hypothesis respx || echo "pip install test deps failed"
###ACTION_DELIMITER###
echo "=== Auto-detecting and installing missing dependencies ==="
# Run a quick collection check to find missing dependencies
echo "Running pytest --collect-only to detect missing dependencies..."
MISSING_DEPS=$(python -m pytest --collect-only $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME 2>&1 | \
    grep "ModuleNotFoundError: No module named" | \
    grep -oE "No module named '[a-zA-Z0-9_]+'" | \
    sed "s/No module named '//g" | \
    sed "s/'//g" | \
    sort -u || true)
if [ -n "$MISSING_DEPS" ]; then
    echo "Found missing modules:"
    echo "$MISSING_DEPS"
    echo "Installing missing dependencies..."
    # Map common module names to package names
    for module in $MISSING_DEPS; do
        # Skip empty or invalid module names
        if [ -z "$module" ] || [[ "$module" =~ ^[^a-zA-Z0-9] ]]; then
            continue
        fi
        case "$module" in
            dotenv) pip install python-dotenv || true ;;
            httpx) pip install httpx || true ;;
            litellm) pip install litellm || true ;;
            freezegun) pip install freezegun || true ;;
            aiohttp) pip install aiohttp || true ;;
            xxhash) pip install xxhash || true ;;
            *) pip install "$module" || echo "Failed to install $module" ;;
        esac
    done
    echo "Dependency installation complete"
else
    echo "No missing dependencies detected"
fi
###ACTION_DELIMITER###
echo 'export PYTHONUNBUFFERED=1' > test_commands.sh
echo 'export PYTHONIOENCODING=utf-8' >> test_commands.sh
echo 'find . -type d -name __pycache__ -exec rm -rf {{}} + 2>/dev/null || true' >> test_commands.sh
echo 'find . -type f -name "*.pyc" -delete 2>/dev/null || true' >> test_commands.sh
echo "python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings | tee /tmp/pytest_output.txt" >> test_commands.sh
###ACTION_DELIMITER###
echo "=== Test command ==="
cat test_commands.sh
###ACTION_DELIMITER###
echo "=== Running test command ==="
bash test_commands.sh || echo "test command failed"
###ACTION_DELIMITER###
echo "=== prepare.sh completed ==="
""".replace("[[REPO_NAME]]", repo_name),
            ),
            File(
                ".",
                "test.patch",
                f"{self.pr.test_patch}",
            ),
            File(
                ".",
                "fix.patch",
                f"{self.pr.fix_patch}",
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
echo "=== Starting run.sh ==="
echo "Current directory: $(pwd)"

if [ ! -d "/home/[[REPO_NAME]]" ]; then
    echo "ERROR: /home/[[REPO_NAME]] directory does not exist!"
    echo "Contents of /home:"
    ls -la /home/
    exit 1
fi

cd /home/[[REPO_NAME]]
echo "Running: python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings"
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
find . -type d -name __pycache__ -exec rm -rf {{}} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true

echo "=== Auto-detecting and installing missing dependencies ==="
MISSING_DEPS=$(python -m pytest --collect-only $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME 2>&1 | \
    grep "ModuleNotFoundError: No module named" | \
    grep -oE "No module named '[a-zA-Z0-9_]+'" | \
    sed "s/No module named '//g" | \
    sed "s/'//g" | \
    sort -u || true)
if [ -n "$MISSING_DEPS" ]; then
    echo "Found missing modules:"
    echo "$MISSING_DEPS"
    echo "Installing missing dependencies..."
    for module in $MISSING_DEPS; do
        # Skip empty or invalid module names
        if [ -z "$module" ] || [[ "$module" =~ ^[^a-zA-Z0-9] ]]; then
            continue
        fi
        case "$module" in
            dotenv) pip install python-dotenv || true ;;
            httpx) pip install httpx || true ;;
            litellm) pip install litellm || true ;;
            freezegun) pip install freezegun || true ;;
            aiohttp) pip install aiohttp || true ;;
            xxhash) pip install xxhash || true ;;
            *) pip install "$module" || echo "Failed to install $module" ;;
        esac
    done
    echo "Dependency installation complete"
else
    echo "No missing dependencies detected"
fi
###ACTION_DELIMITER###

python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings | tee /tmp/pytest_output.txt || echo "pytest exited with code: $?"
echo "=== run.sh completed ==="
""".replace("[[REPO_NAME]]", repo_name),
            ),
            File(
                ".",
                "test-run.sh",
                """#!/bin/bash
# Note: Removed set -e to allow script to continue even if commands fail
# This ensures we see what actually fails

echo "=== Starting test-run.sh ==="
echo "Current directory: $(pwd)"

# Ensure git is available
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

echo "=== Checking repository directory ==="
if [ ! -d "/home/[[REPO_NAME]]" ]; then
    echo "ERROR: /home/[[REPO_NAME]] directory does not exist!"
    echo "Contents of /home:"
    ls -la /home/
    exit 1
fi

cd /home/[[REPO_NAME]]
echo "Current directory: $(pwd)"

# Apply test.patch only if it exists and is not empty
echo "=== Applying test.patch ==="
if [ -s /home/test.patch ]; then
    echo "Found test.patch, applying..."
    if ! git apply --whitespace=nowarn /home/test.patch 2>&1; then
        echo "Warning: git apply test.patch failed, trying alternative method..."
        echo "Continuing anyway..."
    fi
else
    echo "No test.patch to apply (empty or missing)"
fi

echo "=== Auto-detecting and installing missing dependencies ==="
# Run a quick collection check to find missing modules
# Use grep -oE to extract only the module name part with a cleaner pattern
MISSING_DEPS=$(python -m pytest --collect-only $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME 2>&1 | \
    grep "ModuleNotFoundError: No module named" | \
    grep -oE "No module named '[a-zA-Z0-9_]+'" | \
    sed "s/No module named '//g" | \
    sed "s/'//g" | \
    sort -u || true)
if [ -n "$MISSING_DEPS" ]; then
    echo "Found missing modules:"
    echo "$MISSING_DEPS"
    echo "Installing missing dependencies..."
    for module in $MISSING_DEPS; do
        # Skip empty or invalid module names
        if [ -z "$module" ] || [[ "$module" =~ ^[^a-zA-Z0-9] ]]; then
            continue
        fi
        case "$module" in
            dotenv) pip install python-dotenv || true ;;
            httpx) pip install httpx || true ;;
            litellm) pip install litellm || true ;;
            freezegun) pip install freezegun || true ;;
            aiohttp) pip install aiohttp || true ;;
            xxhash) pip install xxhash || true ;;
            *) pip install "$module" || echo "Failed to install $module" ;;
        esac
    done
    echo "Dependency installation complete"
else
    echo "No missing dependencies detected"
fi
###ACTION_DELIMITER###

echo "=== Running pytest ==="
echo "Command: python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings"
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
find . -type d -name __pycache__ -exec rm -rf {{}} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings | tee /tmp/pytest_output.txt || echo "pytest exited with code: $?"
echo "=== test-run.sh completed ==="
""".replace("[[REPO_NAME]]", repo_name),
            ),
            File(
                ".",
                "fix-run.sh",
                """#!/bin/bash
# Note: Removed set -e to allow script to continue even if commands fail
# This ensures we see what actually fails

echo "=== Starting fix-run.sh ==="
echo "Current directory: $(pwd)"

# Ensure git is available
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

echo "=== Checking repository directory ==="
if [ ! -d "/home/[[REPO_NAME]]" ]; then
    echo "ERROR: /home/[[REPO_NAME]] directory does not exist!"
    echo "Contents of /home:"
    ls -la /home/
    exit 1
fi

cd /home/[[REPO_NAME]]
echo "Current directory: $(pwd)"

# Apply patches: test.patch (if exists) and fix.patch
echo "=== Applying patches ==="
if [ -s /home/test.patch ]; then
    echo "Found test.patch, trying to apply both patches..."
    if ! git apply --whitespace=nowarn /home/test.patch /home/fix.patch 2>&1; then
        echo "Warning: git apply both patches failed, trying fix.patch only..."
        if ! git apply --whitespace=nowarn /home/fix.patch 2>&1; then
            echo "Warning: git apply fix.patch also failed"
            echo "Continuing without patches..."
        fi
    fi
else
    echo "No test.patch found, applying fix.patch only..."
    if ! git apply --whitespace=nowarn /home/fix.patch 2>&1; then
        echo "Warning: git apply fix.patch failed"
        echo "Continuing without patch..."
    fi
fi

echo "=== Auto-detecting and installing missing dependencies ==="
# Run a quick collection check to find missing modules
# Use grep -oE to extract only the module name part with a cleaner pattern
MISSING_DEPS=$(python -m pytest --collect-only $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME 2>&1 | \
    grep "ModuleNotFoundError: No module named" | \
    grep -oE "No module named '[a-zA-Z0-9_]+'" | \
    sed "s/No module named '//g" | \
    sed "s/'//g" | \
    sort -u || true)
if [ -n "$MISSING_DEPS" ]; then
    echo "Found missing modules:"
    echo "$MISSING_DEPS"
    echo "Installing missing dependencies..."
    for module in $MISSING_DEPS; do
        # Skip empty or invalid module names
        if [ -z "$module" ] || [[ "$module" =~ ^[^a-zA-Z0-9] ]]; then
            continue
        fi
        case "$module" in
            dotenv) pip install python-dotenv || true ;;
            httpx) pip install httpx || true ;;
            litellm) pip install litellm || true ;;
            freezegun) pip install freezegun || true ;;
            aiohttp) pip install aiohttp || true ;;
            xxhash) pip install xxhash || true ;;
            *) pip install "$module" || echo "Failed to install $module" ;;
        esac
    done
    echo "Dependency installation complete"
else
    echo "No missing dependencies detected"
fi
###ACTION_DELIMITER###

echo "=== Running pytest ==="
echo "Command: python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings"
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
find . -type d -name __pycache__ -exec rm -rf {{}} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
python -u -m pytest -v --tb=short --basetemp=/tmp $TEST_DIR/ $IGNORE_E2E $IGNORE_RUNTIME -p no:warnings | tee /tmp/pytest_output.txt || echo "pytest exited with code: $?"
echo "=== fix-run.sh completed ==="
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


@Instance.register("{{ORG}}", "{{REPO}}")
class InstanceTemplate(Instance):
    # Python version for this repository (extracted from pyproject.toml)
    python_version = "{{PYTHON_VERSION}}"

    def __init__(self, pr: PullRequest, config: Config, *args, **kwargs):
        super().__init__()
        self._pr = pr
        self._config = config
        # Set python_version on the PR object for Image classes to use
        self._pr.python_version = self.__class__.python_version

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

        # Regex patterns to match test cases - supports both test/ and tests/ directories
        pattern1 = re.compile(
            r"((?:test|tests)/[^:]+::[^ ]+)\s+(PASSED|FAILED|SKIPPED|XFAIL)\b"
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
        # Format: "ERROR tests/test_module.py" or "ERROR test/test_module.py"
        error_pattern = re.compile(r"^ERROR\s+((?:test|tests)/[^:]+::[^ ]+)\b", re.MULTILINE)
        for match in error_pattern.finditer(log):
            test_name = match.group(1)
            failed_tests.add(test_name)

        # Also capture "ERROR tests/test_module.py" without the test name
        error_file_pattern = re.compile(r"^ERROR\s+((?:test|tests)/[^.]+\.py)\b", re.MULTILINE)
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
sed -i "" "s/{{REPO}}/$REPO/g"  "$TARGET_FILE" 2>/dev/null || sed -i "s/{{REPO}}/$REPO/g" "$TARGET_FILE"
sed -i "" "s/{{PYTHON_VERSION}}/$PYTHON_VERSION/g"  "$TARGET_FILE" 2>/dev/null || sed -i "s/{{PYTHON_VERSION}}/$PYTHON_VERSION/g" "$TARGET_FILE"

# Replace test directory variables with detected values
# Use different delimiter and escape $ properly for sed
echo "📝 Replacing TEST_DIR=$TEST_DIR, IGNORE_E2E=$IGNORE_E2E, IGNORE_RUNTIME=$IGNORE_RUNTIME"
sed -i "" 's|\$TEST_DIR|'"$TEST_DIR"'|g' "$TARGET_FILE" 2>/dev/null || sed -i 's|\$TEST_DIR|'"$TEST_DIR"'|g' "$TARGET_FILE"
sed -i "" 's|\$IGNORE_E2E|'"$IGNORE_E2E"'|g' "$TARGET_FILE" 2>/dev/null || sed -i 's|\$IGNORE_E2E|'"$IGNORE_E2E"'|g' "$TARGET_FILE"
sed -i "" 's|\$IGNORE_RUNTIME|'"$IGNORE_RUNTIME"'|g' "$TARGET_FILE" 2>/dev/null || sed -i 's|\$IGNORE_RUNTIME|'"$IGNORE_RUNTIME"'|g' "$TARGET_FILE"

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

exit 0