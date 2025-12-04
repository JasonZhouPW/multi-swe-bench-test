##chmod +x build_dataset.sh
##./build_dataset.sh mark3labs__mcp-go_raw_dataset.jsonl

#!/usr/bin/env bash
set -euo pipefail

##########################################
# 参数输入检查
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

RAW_FILE="$1"

# 确认文件存在
if [ ! -f "./data/raw_datasets/$RAW_FILE" ]; then
    echo "❌ Error: ./data/raw_datasets/$RAW_FILE not found"
    exit 1
fi

##########################################
# 自动推导变量
##########################################

# raw 文件名去掉后缀 _raw_dataset.jsonl → 标准 dataset 名称
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

# config 文件名
CONFIG_FILE="config_${BASE_NAME}.json"

# 输出 dataset 文件名
OUTPUT_FILE="./data/output/${BASE_NAME}_dataset.jsonl"

##########################################
# 生成 config JSON
##########################################
echo "📄 Generating config file: $CONFIG_FILE"

cat > "$CONFIG_FILE" << EOF
{
    "mode": "dataset",
    "workdir": "./data/workdir",
    "raw_dataset_files": [
        "./data/raw_datasets/$RAW_FILE"
    ],
    "force_build": false,
    "output_dir": "./data/output",
    "specifics": [],
    "skips": [],
    "repo_dir": "./data/repos",
    "need_clone": false,
    "global_env": [],
    "clear_env": true,
    "stop_on_error": true,
    "max_workers": 2,
    "max_workers_build_image": 8,
    "max_workers_run_instance": 8,
    "log_dir": "./data/logs",
    "log_level": "DEBUG"
}
EOF

##########################################
# 执行构建
##########################################
echo "🚀 Running dataset builder..."
python -m multi_swe_bench.harness.build_dataset --config "$CONFIG_FILE"

##########################################
# 输出构建结果
##########################################
echo "======================================="
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Dataset build completed successfully!"
    echo "Output file: $OUTPUT_FILE"
else
    echo "⚠️  Build finished, but output file not found:"
    echo "$OUTPUT_FILE"
fi
echo "======================================="