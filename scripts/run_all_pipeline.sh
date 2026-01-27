#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="./data/raw_datasets"

echo "========================================="
echo "🔍 扫描 Raw Dataset 目录: $RAW_DIR"
echo "========================================="

shopt -s nullglob
RAW_DATASETS=("$RAW_DIR"/*_raw_dataset.jsonl)
shopt -u nullglob

if [ ${#RAW_DATASETS[@]} -eq 0 ]; then
    echo "❌ Error: No *_raw_dataset.jsonl found in $RAW_DIR"
    exit 1
fi

echo "发现 ${#RAW_DATASETS[@]} 个 raw_dataset 文件："
printf '%s\n' "${RAW_DATASETS[@]}"
echo ""

#############################################
# 逐个执行 run_full_pipeline.sh
#############################################
for RAW_FILE_PATH in "${RAW_DATASETS[@]}"; do
    RAW_FILE_NAME=$(basename "$RAW_FILE_PATH")

    echo "========================================="
    echo "🚀 处理文件: $RAW_FILE_NAME"
    echo "========================================="

    ./run_full_pipeline.sh "$RAW_FILE_NAME"

    echo ""
    echo "-----------------------------------------"
    echo "✔ 完成处理：$RAW_FILE_NAME"
    echo "-----------------------------------------"
    echo ""
done

echo ""
echo "========================================="
echo "🎉 所有 raw_dataset 文件处理完成！"
echo "结果已生成在 ./data/output/ 与 ./data/final_output/"
echo "========================================="