#!/bin/bash
set -e

ROOT_DIR="data/raw_datasets/catchorg__go"
OUTPUT_DIR="data/raw_datasets/all_raw_datasets_go"

echo "Collecting *_raw_dataset.jsonl from $ROOT_DIR ..."
mkdir -p "$OUTPUT_DIR"

# 遍历所有 *_raw_dataset.jsonl
find "$ROOT_DIR" -type f -name "*_raw_dataset.jsonl" | while read -r FILE; do
    # 取上级目录名作为前缀（例如 github__github-mcp-server）
    DIR_NAME=$(basename "$(dirname "$FILE")")

    # 取文件名
    BASE_FILE=$(basename "$FILE")

    # 生成新文件名，避免覆盖：例如 github__github-mcp-server__raw_dataset.jsonl
    NEW_FILE="${DIR_NAME}__${BASE_FILE}"

    echo "Copy: $FILE -> $OUTPUT_DIR/$NEW_FILE"
    cp "$FILE" "$OUTPUT_DIR/$NEW_FILE"
done

echo "Done! All raw_dataset.jsonl have been collected into $OUTPUT_DIR"