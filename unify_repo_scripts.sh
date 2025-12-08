#!/usr/bin/env bash
set -euo pipefail

DATASET_DIR="./data/raw_datasets"

# Worker scripts
AUTO_ADD_IMPORT="./data_pipeline/auto_add_import.sh"
CREATE_ORG_DIR="./data_pipeline/create_org_dir.sh"
GEN_INSTANCE="./data_pipeline/gen_instance_from_dataset_golang.sh"

chmod +x "$AUTO_ADD_IMPORT" "$CREATE_ORG_DIR" "$GEN_INSTANCE"

echo "🚀 Starting unified pipeline (scan ONLY *raw_dataset* files)"
echo "📂 Dataset directory: $DATASET_DIR"
echo ""

FOUND=false

for RAW_FILE in "$DATASET_DIR"/*raw_dataset*.jsonl; do
    if [[ "$RAW_FILE" == "$DATASET_DIR/*raw_dataset*.jsonl" ]]; then
        echo "❌ No raw_dataset files found in $DATASET_DIR"
        exit 1
    fi

    FOUND=true

    FILENAME=$(basename "$RAW_FILE")
    TEMP_FILE="$DATASET_DIR/temp_single_${FILENAME}"

    echo "=============================================="
    echo "📘 Processing raw dataset: $FILENAME"
    echo "=============================================="

    # Extract only first line
    echo "📌 Extracting first record → $TEMP_FILE"
    head -n 1 "$RAW_FILE" > "$TEMP_FILE"

    # ----------------------------------------
    # Step 1
    echo "🔧 Step 1: auto_add_import.sh..."
    "$AUTO_ADD_IMPORT" "$TEMP_FILE"
    echo ""

    # Step 2
    echo "📂 Step 2: create_org_dir.sh..."
    "$CREATE_ORG_DIR" "$TEMP_FILE"
    echo ""

    # Step 3
    echo "🧬 Step 3: gen_instance_from_dataset_golang.sh..."
    "$GEN_INSTANCE" "$TEMP_FILE"
    echo ""

    # ----------------------------------------
    # 🧹 自动清理临时文件
    echo "🧹 Cleaning temp file: $TEMP_FILE"
    rm -f "$TEMP_FILE"
    echo "✔ Temp file removed."
    echo ""

    echo "🎉 Finished processing: $FILENAME"
    echo ""
done

if [ "$FOUND" = false ]; then
    echo "❌ No valid *raw_dataset* files found. Nothing processed."
    exit 1
fi

echo "🏁 All raw_dataset files processed successfully!"