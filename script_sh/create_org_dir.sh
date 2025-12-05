#!/usr/bin/env bash
set -euo pipefail

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

echo "📘 Processing raw dataset: $RAW_FILE"
echo ""

while IFS= read -r line; do
    # 从 raw_dataset 的嵌套结构提取 org 和 language
    ORG=$(echo "$line" | jq -r '.org')
    LANG_RAW=$(echo "$line" | jq -r '.base.repo.language')

    if [ "$ORG" == "null" ] || [ -z "$ORG" ]; then
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

    BASE_DIR="multi_swe_bench/harness/repos/${LANG}"
    ORG_DIR="${BASE_DIR}/${ORG}"
    INIT_FILE="${ORG_DIR}/__init__.py"

    echo "📂 Creating directory: $ORG_DIR"
    mkdir -p "$ORG_DIR"

    IMPORT_LINE="from multi_swe_bench.harness.repos.${LANG}.${ORG}.mcp_go import *"

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