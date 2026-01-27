#!/usr/bin/env bash
set -euo pipefail

##########################################
# 参数输入检查
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    echo "         $0 data/raw_datasets/mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

##########################################
# 自动处理路径与文件名
##########################################
RAW_PATH="$1"

# 如果传入的是相对路径，则保持相对；如果是文件名，则补默认路径
if [ ! -f "$RAW_PATH" ]; then
    # 尝试在默认目录查找
    if [ -f "./data/raw_datasets/$RAW_PATH" ]; then
        RAW_PATH="./data/raw_datasets/$RAW_PATH"
    else
        echo "❌ Error: Cannot find file: $RAW_PATH"
        exit 1
    fi
fi

# 解析出文件名和目录
RAW_FILE="$(basename "$RAW_PATH")"
RAW_DIR="$(dirname "$RAW_PATH")"

##########################################
# 自动推导变量
##########################################
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

WORKDIR="./data/workdir"
OUTPUT_DIR="./data/datasets"
LOG_DIR="./data/logs"
REPO_DIR="./data/repos"
TEMP_DIR="./data/temp_dataset"

mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$TEMP_DIR"

FINAL_OUTPUT="${OUTPUT_DIR}/${BASE_NAME}_dataset.jsonl"
: > "$FINAL_OUTPUT"

echo "🚀 Multi-record dataset builder"
echo "📌 Input file: $RAW_PATH"
echo ""

##########################################
# 获取行数
##########################################
LINE_COUNT=$(wc -l < "$RAW_PATH" | tr -d ' ')
echo "📌 Total records: $LINE_COUNT"
echo ""

if [ "$LINE_COUNT" -eq 0 ]; then
    echo "❌ No data in file."
    exit 1
fi

##########################################
# 遍历每条 JSONL
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
    # 清洗 JSON：jq -c 使其成为合法单行 JSON
    ##########################################
    echo "$LINE" | jq -c '.' > "$TEMP_RAW_FILE"

    ##########################################
    # 生成 config 文件
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
    # 执行单条构建
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
# 总结输出
##########################################
echo "======================================="
echo "🎉 Multi-record dataset build completed"
echo "📦 Output file: $FINAL_OUTPUT"
echo "======================================="