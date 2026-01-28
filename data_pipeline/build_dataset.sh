#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the project root
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure multi_swe_bench is in PYTHONPATH
export PYTHONPATH="$PROJ_ROOT${PYTHONPATH:+:$PYTHONPATH}"

##########################################
# Check input arguments
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    echo "         $0 data/raw_datasets/mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

##########################################
# Automatically handle paths and filenames
##########################################
RAW_PATH="$1"

    # If a relative path is passed, keep it; if only a filename, use default path
    if [ ! -f "$RAW_PATH" ]; then
        # Try finding it in the default directory
        if [ -f "./data/raw_datasets/$RAW_PATH" ]; then
            RAW_PATH="./data/raw_datasets/$RAW_PATH"
    else
        echo "❌ Error: Cannot find file: $RAW_PATH"
        exit 1
    fi
fi

# Parse filename and directory
RAW_FILE="$(basename "$RAW_PATH")"
RAW_DIR="$(dirname "$RAW_PATH")"

##########################################
# Automatically derive variables
##########################################
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

WORKDIR="$PROJ_ROOT/data/workdir"
OUTPUT_DIR="$PROJ_ROOT/data/datasets"
LOG_DIR="$PROJ_ROOT/data/logs"
REPO_DIR="$PROJ_ROOT/data/repos"
TEMP_DIR="$PROJ_ROOT/data/temp_dataset"

mkdir -p "$WORKDIR" "$OUTPUT_DIR" "$LOG_DIR" "$REPO_DIR" "$TEMP_DIR"

FINAL_OUTPUT="${OUTPUT_DIR}/${BASE_NAME}_dataset.jsonl"
: > "$FINAL_OUTPUT"

echo "🚀 Multi-record dataset builder"
echo "📌 Input file: $RAW_PATH"
echo ""

##########################################
# Get line count
##########################################
LINE_COUNT=$(wc -l < "$RAW_PATH" | tr -d ' ')
echo "📌 Total records: $LINE_COUNT"
echo ""

if [ "$LINE_COUNT" -eq 0 ]; then
    echo "❌ No data in file."
    exit 1
fi

##########################################
# Iterate through each JSONL line
##########################################
index=0
while IFS= read -r LINE; do
    echo "============================================"
    echo "📄 Processing record #$index"
    echo "============================================"

    TEMP_RAW_FILE="$TEMP_DIR/${BASE_NAME}_single_${index}.jsonl"
    CONFIG_FILE="$TEMP_DIR/config_${BASE_NAME}_${index}.json"
    SINGLE_OUT="${OUTPUT_DIR}/${BASE_NAME}_${index}_dataset.jsonl"

    ##########################################
    # Clean JSON: use jq -c to ensure valid single-line JSON
    ##########################################
    echo "$LINE" | jq -c '.' > "$TEMP_RAW_FILE"

    ##########################################
    # Generate config file
    ##########################################
    cat > "$CONFIG_FILE" << EOF
{
    "mode": "dataset",
    "workdir": "$WORKDIR",
    "raw_dataset_files": [
        "$TEMP_RAW_FILE"
    ],
    "force_build": false,
    "output_dir": "$OUTPUT_DIR",
    "specifics": [],
    "skips": [],
    "repo_dir": "$REPO_DIR",
    "need_clone": false,
    "global_env": [],
    "clear_env": true,
    "stop_on_error": true,
    "max_workers": 2,
    "max_workers_build_image": 8,
    "max_workers_run_instance": 8,
    "log_dir": "$LOG_DIR",
    "log_level": "DEBUG"
}
EOF

    ##########################################
    # Execute single build
    ##########################################
    echo "🚀 Running dataset builder for record #$index..."
    python -m multi_swe_bench.harness.build_dataset --config "$CONFIG_FILE"

    if [ -f "$SINGLE_OUT" ]; then
        echo "📌 Appending #$index → $FINAL_OUTPUT"
        cat "$SINGLE_OUT" >> "$FINAL_OUTPUT"
        rm -f "$SINGLE_OUT"
    else
        echo "⚠️ Warning: record #$index failed to produce dataset."
    fi

    index=$((index + 1))
    echo ""
done < "$RAW_PATH"

rm -rf "$TEMP_DIR"

##########################################
# Summary output
##########################################
echo "======================================="
echo "🎉 Multi-record dataset build completed"
echo "📦 Output file: $FINAL_OUTPUT"
echo "======================================="