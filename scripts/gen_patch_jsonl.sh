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
# Derive output filename
#############################################
BASENAME=$(basename "$PATCH_FILE" .patch)
OUTPUT_FILE="${BASENAME}_patch.jsonl"

echo "📄 Output file: $OUTPUT_FILE"

#############################################
# Read the first line's fields from the raw dataset
#############################################
FIRST_LINE=$(head -n 1 "$RAW_DATASET")

ORG=$(echo "$FIRST_LINE" | jq -r '.org')
REPO=$(echo "$FIRST_LINE" | jq -r '.repo')
NUMBER=$(echo "$FIRST_LINE" | jq -r '.number')

#############################################
# Read the entire patch content (preserving newlines)
#############################################
PATCH_CONTENT=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$PATCH_FILE" | awk '{print}' ORS='\\n')

#############################################
# Write to JSONL
#############################################
cat > "$OUTPUT_FILE" << EOF
{"org":"$ORG","repo":"$REPO","number":$NUMBER,"fix_patch":"$PATCH_CONTENT"}
EOF

echo "✅ Done! Generated $OUTPUT_FILE"