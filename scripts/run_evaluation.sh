#!/usr/bin/env bash
set -euo pipefail

##########################################
# Argument validation
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_dataset.jsonl"
    exit 1
fi

DATASET_FILE="$1"
DATASET_PATH="./data/datasets/$DATASET_FILE"

if [ ! -f "$DATASET_PATH" ]; then
    echo "❌ Error: dataset file not found: $DATASET_PATH"
    exit 1
fi

##########################################
# Automatically derive patch file: <base>_patch.jsonl
##########################################
BASE_NAME="${DATASET_FILE%%_dataset.jsonl}"
PATCH_FILE="${BASE_NAME}_patch.jsonl"
PATCH_PATH="./data/patches/$PATCH_FILE"

if [ ! -f "$PATCH_PATH" ]; then
    echo "❌ Error: patch file not found: $PATCH_PATH"
    exit 1
fi

##########################################
# ev_config filename
##########################################
EV_CONFIG="ev_config_${BASE_NAME}.json"

##########################################
# Generate ev_config JSON
##########################################
echo "📄 Generating evaluation config: $EV_CONFIG"

cat > "$EV_CONFIG" << EOF
{
    "mode": "evaluation",
    "workdir": "./data/workdir",
    "patch_files": [
        "$PATCH_PATH"
    ],
    "dataset_files": [
        "$DATASET_PATH"
    ],
    "force_build": true,
    "output_dir": "./data/final_output",
    "specifics": [],
    "skips": [],
    "repo_dir": "./data/repos",
    "need_clone": false,
    "global_env": [],
    "clear_env": true,
    "stop_on_error": true,
    "max_workers": 8,
    "max_workers_build_image": 8,
    "max_workers_run_instance": 8,
    "log_dir": "./data/logs",
    "log_level": "DEBUG"
}
EOF

##########################################
# Execute Evaluation
##########################################
echo "🚀 Running evaluation..."
python -m multi_swe_bench.harness.run_evaluation --config "$EV_CONFIG"

##########################################
# Output results
##########################################
REPORT_DIR="./data/final_output"

echo "========================================="
echo "✅ Evaluation completed!"
echo "Results stored in:"
echo "$REPORT_DIR"
echo "========================================="