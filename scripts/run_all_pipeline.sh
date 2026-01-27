#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="./data/raw_datasets"

echo "========================================="
echo "🔍 Scanning Raw Dataset directory: $RAW_DIR"
echo "========================================="

shopt -s nullglob
RAW_DATASETS=("$RAW_DIR"/*_raw_dataset.jsonl)
shopt -u nullglob

if [ ${#RAW_DATASETS[@]} -eq 0 ]; then
    echo "❌ Error: No *_raw_dataset.jsonl found in $RAW_DIR"
    exit 1
fi

echo "Found ${#RAW_DATASETS[@]} raw_dataset files:"
printf '%s\n' "${RAW_DATASETS[@]}"
echo ""

#############################################
# Execute run_full_pipeline.sh for each file
#############################################
for RAW_FILE_PATH in "${RAW_DATASETS[@]}"; do
    RAW_FILE_NAME=$(basename "$RAW_FILE_PATH")

    echo "========================================="
    echo "🚀 Processing file: $RAW_FILE_NAME"
    echo "========================================="

    ./run_full_pipeline.sh "$RAW_FILE_NAME"

    echo ""
    echo "-----------------------------------------"
    echo "✔ Completed: $RAW_FILE_NAME"
    echo "-----------------------------------------"
    echo ""
done

echo ""
echo "========================================="
echo "🎉 All raw_dataset files processed!"
echo "Results generated in ./data/output/ and ./data/final_output/"
echo "========================================="