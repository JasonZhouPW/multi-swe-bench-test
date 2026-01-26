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

# 将名称 sanitize 成合法的 package/dir 名（主要用于 python 导入 & 文件夹安全）
# - 把非字母数字和下划线替换成下划线
# - 转小写（Python 包名通常小写）
# - 若以数字开头，前面加下划线
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

# 确保目录与 __init__.py（若为 python 包）存在
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
    # 从 raw_dataset 的嵌套结构提取 org 和 language
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

    # 映射语言
    LANG=$(map_language "$LANG_RAW")

    if [ "$LANG" == "unknown" ]; then
        echo "❌ Unsupported language: $LANG_RAW — Skipping"
        continue
    fi

    # 对 org/repo 做安全化处理（用于目录与 import 路径）
    ORG=$(sanitize_name "$ORG_RAW")
    REPO=$(sanitize_name "$REPO_RAW")

    BASE_DIR="$PROJ_ROOT/multi_swe_bench/harness/repos/${LANG}"
    ORG_DIR="${BASE_DIR}/${ORG}"
    REPO_DIR="${ORG_DIR}/${REPO}"
    INIT_FILE="${ORG_DIR}/__init__.py"

    echo "📂 Creating directory: $REPO_DIR"
    # 如果是 python，我们会在所有层级创建 __init__.py；对其他语言也创建目录（但不会强制 __init__ 创建）
    mkdir -p "$REPO_DIR"
    # 如果是 python，确保每一层都是包
    if [ "$LANG" == "python" ]; then
        ensure_package_dirs "$BASE_DIR/$ORG"
        ensure_package_dirs "$REPO_DIR"
    else
        # 为保持一致也创建 org 的 __init__.py（可选）
        touch "$INIT_FILE" 2>/dev/null || true
    fi

    # 构造 import line（使用已 sanitize 的名称，保证有效）
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