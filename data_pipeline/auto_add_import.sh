#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the project root
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RAW_JSON="$1"

if [ ! -f "$RAW_JSON" ]; then
    echo "❌ Error: raw dataset file not found: $RAW_JSON"
    exit 1
fi

##########################################
# 从 raw dataset 读取 org / repo / language
##########################################
LINE=$(head -n 1 "$RAW_JSON")

ORG=$(echo "$LINE" | sed -n 's/.*"org": *"\([^"]*\)".*/\1/p')
REPO=$(echo "$LINE" | sed -n 's/.*"repo": *"\([^"]*\)".*/\1/p')
LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')

if [ -z "$ORG" ] || [ -z "$REPO" ]; then
    echo "❌ Error: cannot extract org/repo from JSON"
    exit 1
fi

if [ -z "$LANG_RAW" ]; then
    echo "⚠️ Warning: no 'language' field found, defaulting to golang"
    LANG_RAW="golang"
fi

LANG=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')

echo "🔍 Extracted:"
echo "  ORG      = $ORG"
echo "  REPO     = $REPO"
echo "  LANGUAGE = $LANG"

##########################################
# Python import 兼容包名格式转换
##########################################
ORG_PY=$(echo "$ORG" | tr '-' '_' | tr 'A-Z' 'a-z')
REPO_PY=$(echo "$REPO" | tr '-' '_' | tr '.' '_' | tr 'A-Z' 'a-z')

##########################################
# 语言映射：raw → 目录名
##########################################
case "$LANG" in
    go|golang)
        LANG_DIR="golang"
        ;;
    python|py)
        LANG_DIR="python"
        ;;
    rust)
        LANG_DIR="rust"
        ;;
    java)
        LANG_DIR="java"
        ;;
    javascript|js|node|nodejs)
        LANG_DIR="javascript"
        ;;
    cpp|c++|c)
        LANG_DIR="cpp"
        ;;
    typescript|TypeScript|ts)
        LANG_DIR="typescript"
        ;;
    *)
        echo "❌ Unsupported language: $LANG_RAW"
        exit 1
        ;;
esac

##########################################
# 创建目录结构 multi_swe_bench/harness/repos/<lang>/<org>
##########################################
BASE_DIR="$PROJ_ROOT/multi_swe_bench/harness/repos/$LANG_DIR"
ORG_DIR="$BASE_DIR/$ORG_PY"

mkdir -p "$ORG_DIR"

##########################################
# 修改对应语言的 __init__.py
##########################################
INIT_FILE="$BASE_DIR/__init__.py"

if [ ! -f "$INIT_FILE" ]; then
    echo "⚠️ __init__.py not found, creating: $INIT_FILE"
    echo "" > "$INIT_FILE"
fi

IMPORT_LINE="from multi_swe_bench.harness.repos.${LANG_DIR}.${ORG_PY}.${REPO_PY} import *"

##########################################
# 防止重复添加
##########################################
if grep -Fxq "$IMPORT_LINE" "$INIT_FILE"; then
    echo "ℹ️ Already exists in __init__.py"
else
    echo "$IMPORT_LINE" >> "$INIT_FILE"
    echo "✅ Added import to $INIT_FILE:"
    echo "   $IMPORT_LINE"
fi

echo "🎉 Completed!"