#!/usr/bin/env bash
set -euo pipefail

##########################################
# Argument validation (only 1 argument required: full .jsonl path)
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_path.jsonl>"
    echo "Example: $0 data/raw_datasets/mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

RAW_DATASET_PATH="$1"

if [ ! -f "$RAW_DATASET_PATH" ]; then
    echo "❌ Error: raw dataset file not found: $RAW_DATASET_PATH"
    exit 1
fi

echo "📌 Using raw dataset: $RAW_DATASET_PATH"


##########################################
# Automatically split directory and filename
##########################################
RAW_DIR="$(dirname "$RAW_DATASET_PATH")/"
RAW_FILE="$(basename "$RAW_DATASET_PATH")"

echo "📁 RAW_DIR  = $RAW_DIR"
echo "📄 RAW_FILE = $RAW_FILE"


##########################################
# Automatically derive BASE_NAME (remove _raw_dataset.jsonl)
##########################################
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

##########################################
# Automatically derive patch/dataset JSONL
##########################################
PATCH_JSONL="data/patches/${BASE_NAME}_patch.jsonl"
DATASET_PATH="data/datasets/${BASE_NAME}_dataset.jsonl"
OUTPUT_DIR="data/output"

mkdir -p "$OUTPUT_DIR"

##########################################
# Check if patch JSONL exists
##########################################
echo "🔍 Checking patch JSONL: $PATCH_JSONL"
if [ ! -f "$PATCH_JSONL" ]; then
    echo "❌ Error: patch JSONL not found: $PATCH_JSONL"
    echo "💡 Please generate it first using gen_patch_jsonl.sh"
    exit 1
fi

##########################################
# Check if dataset JSONL exists
##########################################
echo "🔍 Checking dataset JSONL: $DATASET_PATH"
if [ ! -f "$DATASET_PATH" ]; then
    echo "❌ Error: dataset JSONL not found: $DATASET_PATH"
    echo "💡 Please generate it first using gen_dataset_jsonl.sh"
    exit 1
fi

##########################################
# STEP: Run evaluation
##########################################
echo "========================================="
echo "🚀 Running evaluation..."
echo "========================================="

# Define SCRIPT_DIR for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# run_evaluation.sh requires dataset_file.jsonl (filename, not path)
DATASET_FILE_BASENAME="${BASE_NAME}_dataset.jsonl"

echo -e "\n${CYAN}Step 3: Running Evaluation...${NC}"
"$SCRIPT_DIR/../data_pipeline/run_evaluation.sh" "$DATASET_FILE_BASENAME"


##########################################
# Final output
##########################################
echo "========================================="
echo "🎉 All tasks completed successfully!"
echo "Raw dataset: $RAW_DATASET_PATH"
echo "Patch JSON:  $PATCH_JSONL"
echo "Dataset:     $DATASET_PATH"
echo "Output Dir:  $OUTPUT_DIR"
echo "========================================="