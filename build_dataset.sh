##chmod +x build_dataset.sh
##./build_dataset.sh mark3labs__mcp-go_raw_dataset.jsonl

#!/usr/bin/env bash
set -euo pipefail

##########################################
# 输入参数检查
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

RAW_FILE="$1"
RAW_PATH="./data/raw_datasets/$RAW_FILE"

if [ ! -f "$RAW_PATH" ]; then
    echo "❌ Error: $RAW_PATH not found"
    exit 1
fi

##########################################
# 自动推导变量
##########################################
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

WORKDIR="./data/workdir"
OUTPUT_DIR="./data/output"
LOG_DIR="./data/logs"
REPO_DIR="./data/repos"
TEMP_DIR="./data/temp_dataset"

mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$TEMP_DIR"

# 最终合并输出文件
FINAL_OUTPUT="${OUTPUT_DIR}/${BASE_NAME}_dataset.jsonl"

# 清空旧文件
: > "$FINAL_OUTPUT"

echo "🚀 Starting dataset build for multi-record file: $RAW_FILE"
echo ""

##########################################
# 获取 JSONL 行数
##########################################
LINE_COUNT=$(wc -l < "$RAW_PATH" | tr -d ' ')
echo "📌 Total records: $LINE_COUNT"
echo ""

if [ "$LINE_COUNT" -eq 0 ]; then
    echo "❌ Error: no records in dataset file."
    exit 1
fi

##########################################
# 主循环：每条 JSON 独立构建 + 合并输出
##########################################
index=0
while IFS= read -r LINE; do
    echo "============================================"
    echo "📄 Processing record #$index"
    echo "============================================"

    TEMP_RAW_FILE="$TEMP_DIR/${BASE_NAME}_single_${index}.jsonl"
    CONFIG_FILE="$TEMP_DIR/config_${BASE_NAME}_${index}.json"
    SINGLE_OUT="${OUTPUT_DIR}/${BASE_NAME}_${index}_dataset.jsonl"

    # 保存此条 raw 记录
    echo "$LINE" > "$TEMP_RAW_FILE"

    ##########################################
    # 生成针对该条记录的 config
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
    # 执行构建
    ##########################################
    python -m multi_swe_bench.harness.build_dataset --config "$CONFIG_FILE"

    if [ ! -f "$SINGLE_OUT" ]; then
        echo "⚠️  Warning: record #$index did not produce dataset."
    else
        echo "📌 Appending record #$index → $FINAL_OUTPUT"
        cat "$SINGLE_OUT" >> "$FINAL_OUTPUT"
    fi

    # 删除中间产物（可选）
    rm -f "$SINGLE_OUT"

    echo ""
    index=$((index + 1))
done < "$RAW_PATH"

##########################################
# 清理临时目录
##########################################
rm -rf "$TEMP_DIR"

echo "============================================"
echo "🎉 Dataset build completed for: $RAW_FILE"
echo "📦 Final merged dataset:"
echo "➡ $FINAL_OUTPUT"
echo "============================================"