#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <raw_dataset.jsonl> <patch_file.patch>"
    exit 1
fi

RAW_DATASET="$1"
PATCH_FILE="$2"

if [ ! -f "$RAW_DATASET" ]; then
    echo "❌ Raw dataset not found: $RAW_DATASET"
    exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
    echo "❌ Patch file not found: $PATCH_FILE"
    exit 1
fi

#############################################
# 推导输出文件名
#############################################
BASENAME=$(basename "$PATCH_FILE" .patch)
OUTPUT_FILE="${BASENAME}_patch.jsonl"

echo "📄 Output file: $OUTPUT_FILE"

#############################################
# 读取 raw_dataset 的第一行字段
#############################################
FIRST_LINE=$(head -n 1 "$RAW_DATASET")

ORG=$(echo "$FIRST_LINE" | jq -r '.org')
REPO=$(echo "$FIRST_LINE" | jq -r '.repo')
NUMBER=$(echo "$FIRST_LINE" | jq -r '.number')

#############################################
# 读取 PATCH 全部内容（保留换行符）
#############################################
PATCH_CONTENT=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$PATCH_FILE" | awk '{print}' ORS='\\n')

#############################################
# 写入 JSONL
#############################################
cat > "$OUTPUT_FILE" << EOF
{"org":"$ORG","repo":"$REPO","number":$NUMBER,"fix_patch":"$PATCH_CONTENT"}
EOF

echo "✅ Done! Generated $OUTPUT_FILE"