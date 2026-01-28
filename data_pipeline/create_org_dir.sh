#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the project root
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset.jsonl>"
    echo "Example: $0 ./data/raw_datasets/mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

RAW_FILE="$1"

if [ ! -f "$RAW_FILE" ]; then
    echo "❌ Error: raw dataset file not found: $RAW_FILE"
    exit 1
fi

# ---- Language Mapping ----
map_language() {
    case "$1" in
        Go|go|Golang|golang)
            echo "golang"
            ;;
        Python|python)
            echo "python"
            ;;
        Rust|rust)
            echo "rust"
            ;;
        JavaScript|javascript|JS|js)
            echo "javascript"
            ;;
        TypeScript|typescript|ts)
            echo "typescript"
            ;;
        Java|java)
            echo "java"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Sanitize the name into a valid package/dir name (mainly for Python imports & folder safety)
# - Replace non-alphanumeric and non-underscore characters with underscores
# - Convert to lowercase (Python package names are usually lowercase)
# - If it starts with a digit, prefix an underscore
sanitize_name() {
    local name="$1"
    # replace non-alnum/_ with _
    name="$(echo "$name" | sed 's/[^A-Za-z0-9_]/_/g')"
    # to lower-case
    name="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    # if starts with digit, prefix underscore
    if [[ "$name" =~ ^[0-9] ]]; then
        name="_$name"
    fi
    echo "$name"
}

# Ensure directory and __init__.py (if it's a Python package) exist
ensure_package_dirs() {
    local path="$1"
    # create full path
    mkdir -p "$path"
    # create __init__.py for all path components (only if language is python)
    # We'll create __init__.py in each subdir so imports work
    IFS='/' read -r -a parts <<< "$path"
    cur=""
    for p in "${parts[@]}"; do
        cur="$cur/$p"
        # skip if empty (leading slash)
        if [ -z "$p" ]; then
            continue
        fi
        touch "${cur}/__init__.py" 2>/dev/null || true
    done
}

echo "📘 Processing raw dataset: $RAW_FILE"
echo ""

while IFS= read -r line || [ -n "$line" ]; do
    # Extract org and language from the nested structure of raw_dataset
    ORG_RAW=$(echo "$line" | jq -r '.org')
    REPO_RAW=$(echo "$line" | jq -r '.base.repo.name')
    LANG_RAW=$(echo "$line" | jq -r '.base.repo.language')

    if [ "$ORG_RAW" == "null" ] || [ -z "$ORG_RAW" ]; then
        echo "⚠️  Skipped invalid line (missing org): $line"
        continue
    fi

    if [ "$LANG_RAW" == "null" ] || [ -z "$LANG_RAW" ]; then
        echo "⚠️  Skipped invalid line (missing language): $line"
        continue
    fi

    # Map language
    LANG=$(map_language "$LANG_RAW")

    if [ "$LANG" == "unknown" ]; then
        echo "❌ Unsupported language: $LANG_RAW — Skipping"
        continue
    fi

    # Sanitize org/repo (for directory and import paths)
    ORG=$(sanitize_name "$ORG_RAW")
    REPO=$(sanitize_name "$REPO_RAW")

    BASE_DIR="$PROJ_ROOT/multi_swe_bench/harness/repos/${LANG}"
    ORG_DIR="${BASE_DIR}/${ORG}"
    REPO_DIR="${ORG_DIR}/${REPO}"
    INIT_FILE="${ORG_DIR}/__init__.py"

    echo "📂 Creating directory: $REPO_DIR"
    # For Python, we'll create __init__.py at all levels; for other languages, we'll create directories (but won't force __init__.py creation)
    mkdir -p "$REPO_DIR"
    # For Python, ensure every level is a package
    if [ "$LANG" == "python" ]; then
        ensure_package_dirs "$BASE_DIR/$ORG"
        ensure_package_dirs "$REPO_DIR"
    else
        # Also create org's __init__.py for consistency (optional)
        touch "$INIT_FILE" 2>/dev/null || true
    fi

    # Construct import line (using sanitized names to guarantee validity)
    IMPORT_LINE="from multi_swe_bench.harness.repos.${LANG}.${ORG}.${REPO} import *"

    touch "$INIT_FILE"

    if ! grep -Fxq "$IMPORT_LINE" "$INIT_FILE"; then
        echo "$IMPORT_LINE" >> "$INIT_FILE"
        echo "  ➕ Added import to $INIT_FILE"
    else
        echo "  ✔ Import already exists, skipping."
    fi

    echo ""
done < "$RAW_FILE"

echo "✅ All org directories generated successfully!"