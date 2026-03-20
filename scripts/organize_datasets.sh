#!/bin/bash

# Script to organize datasets into final_output directory
# 1. Delete all empty files in data/datasets
# 2. For each remaining dataset file, organize into final_output/YYYY_MM_DD/<org>_<repo>-<pr_number>/image & instance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATASETS_DIR="$BASE_DIR/data/datasets"
WORKDIR_DIR="$BASE_DIR/data/workdir"
FINAL_OUTPUT_DIR="$BASE_DIR/final_output"

# Get current date in YYYY_MM_DD format
CURRENT_DATE=$(date +%Y_%m_%d)

echo "========================================="
echo "🗂️  Organizing Datasets"
echo "========================================="
echo "Date: $CURRENT_DATE"
echo "Datasets dir: $DATASETS_DIR"
echo "Workdir: $WORKDIR_DIR"
echo "Final output: $FINAL_OUTPUT_DIR"
echo ""

##########################################
# Step 1: Delete all empty files in data/datasets
##########################################
echo "📦 Step 1: Deleting empty files in data/datasets..."
EMPTY_COUNT=$(find "$DATASETS_DIR" -maxdepth 1 -type f -name "*.jsonl" -empty | wc -l | tr -d ' ')

if [ "$EMPTY_COUNT" -gt 0 ]; then
    find "$DATASETS_DIR" -maxdepth 1 -type f -name "*.jsonl" -empty -delete
    echo "✅ Deleted $EMPTY_COUNT empty file(s)"
else
    echo "✅ No empty files found"
fi
echo ""

##########################################
# Step 2: Process each remaining dataset file
##########################################
echo "📦 Step 2: Processing dataset files..."

# Create final_output directory if not exists
mkdir -p "$FINAL_OUTPUT_DIR"

# Create date subdirectory
DATE_DIR="$FINAL_OUTPUT_DIR/$CURRENT_DATE"
mkdir -p "$DATE_DIR"
echo "📁 Output directory: $DATE_DIR"
echo ""

# Find all non-empty .jsonl files
for DATASET_FILE in "$DATASETS_DIR"/*.jsonl; do
    # Skip if no files match
    [ -e "$DATASET_FILE" ] || continue

    # Skip if file is empty (double check)
    [ -s "$DATASET_FILE" ] || continue

    FILENAME=$(basename "$DATASET_FILE")
    echo "🔍 Processing: $FILENAME"

    # Extract org and repo from filename (format: org__repo_dataset.jsonl)
    BASE_NAME="${FILENAME%%_dataset.jsonl}"
    ORG="${BASE_NAME%%__*}"
    REPO="${BASE_NAME##*__}"

    echo "   Org: $ORG, Repo: $REPO"

    # Process each record in the dataset file
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # Parse JSON to get pr_number
        PR_NUMBER=$(echo "$line" | jq -r '.number')

        if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ]; then
            echo "   ⚠️  Skipping record: no pr_number found"
            continue
        fi

        # Create directory names
        RECORD_DIR="${ORG}_${REPO}-${PR_NUMBER}"
        RECORD_FULL_PATH="$DATE_DIR/$RECORD_DIR"
        OUTPUT_JSON="$RECORD_FULL_PATH/${RECORD_DIR}_dataset.json"

        # Skip if already processed (dataset JSON file exists)
        if [ -f "$OUTPUT_JSON" ]; then
            echo "   ⏭️  Skipped (already exists): $RECORD_DIR"
            continue
        fi

        # Define source paths
        IMAGE_SRC="$WORKDIR_DIR/$ORG/$REPO/images/pr-$PR_NUMBER"
        INSTANCE_SRC="$WORKDIR_DIR/$ORG/$REPO/instances/pr-$PR_NUMBER"

        # Define destination paths
        IMAGE_DST="$RECORD_FULL_PATH/image"
        INSTANCE_DST="$RECORD_FULL_PATH/instance"

        # Create destination directories
        mkdir -p "$IMAGE_DST"
        mkdir -p "$INSTANCE_DST"

        # Copy image directory contents if exists
        if [ -d "$IMAGE_SRC" ]; then
            cp -r "$IMAGE_SRC"/* "$IMAGE_DST"/ 2>/dev/null || true
            echo "   ✅ Copied image: pr-$PR_NUMBER"
        else
            echo "   ⚠️  Image source not found: $IMAGE_SRC"
        fi

        # Copy instance directory contents if exists
        if [ -d "$INSTANCE_SRC" ]; then
            cp -r "$INSTANCE_SRC"/* "$INSTANCE_DST"/ 2>/dev/null || true
            echo "   ✅ Copied instance: pr-$PR_NUMBER"
        else
            echo "   ⚠️  Instance source not found: $INSTANCE_SRC"
        fi

        # Save dataset record as JSON file in the record directory
        OUTPUT_JSON="$RECORD_FULL_PATH/${RECORD_DIR}_dataset.json"
        echo "$line" | jq '.' > "$OUTPUT_JSON"
        echo "   ✅ Saved dataset: ${RECORD_DIR}_dataset.json"

    done < "$DATASET_FILE"

    echo ""
done

echo "========================================="
echo "✅ Done! Organized datasets in: $DATE_DIR"
echo "========================================="
