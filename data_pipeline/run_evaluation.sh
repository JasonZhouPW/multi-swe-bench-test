#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the project root
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure multi_swe_bench is in PYTHONPATH
export PYTHONPATH="$PROJ_ROOT${PYTHONPATH:+:$PYTHONPATH}"

##########################################
# 参数校验
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_dataset.jsonl"
    exit 1
fi

DATASET_FILE="$1"
DATASET_PATH="$PROJ_ROOT/data/datasets/$DATASET_FILE"

if [ ! -f "$DATASET_PATH" ]; then
    echo "❌ Error: dataset file not found: $DATASET_PATH"
    exit 1
fi

##########################################
# 自动推导 patch 文件：<base>_patch.jsonl
##########################################
BASE_NAME="${DATASET_FILE%%_dataset.jsonl}"
PATCH_FILE="${BASE_NAME}_patch.jsonl"
PATCH_PATH="$PROJ_ROOT/data/patches/$PATCH_FILE"

if [ ! -f "$PATCH_PATH" ]; then
    echo "❌ Error: patch file not found: $PATCH_PATH"
    exit 1
fi

##########################################
# ev_config 文件名
##########################################
EV_CONFIG="ev_config_${BASE_NAME}.json"

##########################################
# 生成 ev_config JSON
##########################################
echo "📄 Generating evaluation config: $EV_CONFIG"

cat > "$EV_CONFIG" << EOF
{
    "mode": "evaluation",
    "workdir": "$PROJ_ROOT/data/workdir",
    "patch_files": [
        "$PATCH_PATH"
    ],
    "dataset_files": [
        "$DATASET_PATH"
    ],
    "force_build": true,
    "output_dir": "$PROJ_ROOT/data/final_output",
    "specifics": [],
    "skips": [],
    "repo_dir": "$PROJ_ROOT/data/repos",
    "need_clone": false,
    "global_env": [],
    "clear_env": true,
    "stop_on_error": true,
    "max_workers": 8,
    "max_workers_build_image": 8,
    "max_workers_run_instance": 8,
    "log_dir": "$PROJ_ROOT/data/logs",
    "log_level": "DEBUG"
}
EOF

##########################################
# 解析数据集文件名 -> 生成输出文件名
##########################################
##########################################
# 解析数据集文件名 -> 生成标准项目名
##########################################
DATASET_PATH="$1"
BASENAME=$(basename "$DATASET_PATH")    # 例如 mark3labs__mcp-go_dataset.jsonl

# 1. 去掉 .jsonl
NAME_NO_SUFFIX="${BASENAME%.jsonl}"     # mark3labs__mcp-go_dataset

# 2. 去掉最后的 "_dataset" 或 "_raw_dataset"（如果有）
PROJECT_NAME="${NAME_NO_SUFFIX%_dataset}"
PROJECT_NAME="${PROJECT_NAME%_raw_dataset}"

OUTPUT_FILENAME="${PROJECT_NAME}_final_report.json"
# 输出目录
REPORT_DIR="$PROJ_ROOT/data/final_output/${PROJECT_NAME}"
mkdir -p "$REPORT_DIR"

##########################################
# 执行 Evaluation
##########################################
echo "🚀 Running evaluation..."
python -m multi_swe_bench.harness.run_evaluation \
    --config "$EV_CONFIG" \
    --output_dir "$REPORT_DIR"

##########################################
# 重命名默认 final_report.json -> 项目名版本
##########################################
DEFAULT_REPORT="${REPORT_DIR}/final_report.json"
TARGET_REPORT="${REPORT_DIR}/${OUTPUT_FILENAME}"

if [ -f "$DEFAULT_REPORT" ]; then
    mv "$DEFAULT_REPORT" "$TARGET_REPORT"
fi

##########################################
# 输出结果
##########################################
echo "========================================="
echo "✅ Evaluation completed!"
echo "Results stored in:"
echo "$TARGET_REPORT"
echo "========================================="