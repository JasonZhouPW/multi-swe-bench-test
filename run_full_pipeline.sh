#!/usr/bin/env bash
set -euo pipefail

##########################################
# 参数校验
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

RAW_FILE="$1"
RAW_DATASET_PATH="./data/test_raw_datasets/$RAW_FILE"

if [ ! -f "$RAW_DATASET_PATH" ]; then
    echo "❌ Error: raw dataset file not found: $RAW_DATASET_PATH"
    exit 1
fi

##########################################
# 自动推导 BASE_NAME（去掉 _raw_dataset.jsonl）
##########################################
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

##########################################
# 推导 patch 源文件
##########################################
PATCH_SRC="./data/patches/${BASE_NAME}.patch"

if [ ! -f "$PATCH_SRC" ]; then
    echo "❌ Error: patch file not found: $PATCH_SRC"
    exit 1
fi

##########################################
# STEP 0: 生成 patch JSONL
##########################################
echo "========================================="
echo "🚀 STEP 0: Generating patch JSONL..."
echo "========================================="

./gen_patch_jsonl.sh "$RAW_DATASET_PATH" "$PATCH_SRC"

PATCH_JSONL="./data/mcp_data/${BASE_NAME}_patch.jsonl"

if [ ! -f "$PATCH_JSONL" ]; then
    echo "❌ Error: patch jsonl not generated: $PATCH_JSONL"
    exit 1
fi

echo "✅ Patch JSONL generated: $PATCH_JSONL"

##########################################
# STEP 1: 构建 dataset（支持多条记录）
##########################################
echo "========================================="
echo "🚀 STEP 1: Building dataset..."
echo "========================================="

./build_dataset.sh "$RAW_FILE"

##########################################
# 推导 dataset 文件名（多条合并在一个文件中）
##########################################
DATASET_FILE="${BASE_NAME}_dataset.jsonl"
DATASET_PATH="./data/output/$DATASET_FILE"

if [ ! -f "$DATASET_PATH" ]; then
    echo "❌ Error: dataset file not generated: $DATASET_PATH"
    exit 1
fi

echo "✅ Dataset generated: $DATASET_PATH"

##########################################
# STEP 1.5: 生成 ev_config.json
##########################################
echo "========================================="
echo "🛠 STEP 1.5: Generating ev_config.json..."
echo "========================================="

cat > ev_config.json <<EOF
{
    "mode": "evaluation",
    "workdir": "./data/workdir",
    "patch_files": [
        "$PATCH_JSONL"
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

echo "✅ ev_config.json generated"

##########################################
# STEP 2: 运行 evaluation
##########################################
echo "========================================="
echo "🚀 STEP 2: Running evaluation..."
echo "========================================="

./run_evaluation.sh ev_config.json

##########################################
# 最终输出
##########################################
echo "========================================="
echo "🎉 All tasks completed successfully!"
echo "Raw dataset: $RAW_DATASET_PATH"
echo "Patch JSON:  $PATCH_JSONL"
echo "Dataset:     $DATASET_PATH"
echo "Evaluation:  ./data/final_output/"
echo "========================================="