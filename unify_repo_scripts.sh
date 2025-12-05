#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

RAW_FILENAME="$1"
RAW_FILE="./data/raw_datasets/$RAW_FILENAME"

if [ ! -f "$RAW_FILE" ]; then
    echo "❌ Error: raw dataset file not found: $RAW_FILE"
    exit 1
fi

# 设置三个脚本的路径
AUTO_ADD_IMPORT="./script_sh/auto_add_import.sh"
CREATE_ORG_DIR="./script_sh/create_org_dir.sh"
GEN_INSTANCE="./script_sh/gen_instance_from_dataset_golang.sh"

echo "🚀 Starting unified pipeline for dataset: $RAW_FILE"
echo ""

# ---- Step 1 ----
echo "🔧 Step 1: Running auto_add_import.sh..."
chmod +x "$AUTO_ADD_IMPORT"
"$AUTO_ADD_IMPORT" "$RAW_FILE"
echo ""

# ---- Step 2 ----
echo "📂 Step 2: Running create_org_dir.sh..."
chmod +x "$CREATE_ORG_DIR"
"$CREATE_ORG_DIR" "$RAW_FILE"
echo ""

# ---- Step 3 ----
echo "🧬 Step 3: Running gen_instance_from_dataset_golang.sh..."
chmod +x "$GEN_INSTANCE"
"$GEN_INSTANCE" "$RAW_FILE"
echo ""

echo "🎉 All steps completed successfully!"