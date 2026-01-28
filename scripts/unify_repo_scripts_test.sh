#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Worker scripts
AUTO_ADD_IMPORT="$SCRIPT_DIR/../data_pipeline/auto_add_import.sh"
CREATE_ORG_DIR="$SCRIPT_DIR/../data_pipeline/create_org_dir.sh"
#GEN_INSTANCE="$SCRIPT_DIR/../data_pipeline/gen_instance_from_dataset_golang.sh"
chmod +x "$AUTO_ADD_IMPORT" "$CREATE_ORG_DIR"

echo "🚀 Starting unified pipeline"

########################################
# Parse input argument
########################################
INPUT=${1:-""}

if [[ -z "$INPUT" ]]; then
    echo "❌ Usage: $0 <raw_dataset_file | dataset_directory>"
    exit 1
fi

########################################
# Detect file or directory
########################################
FILES=()

if [[ -f "$INPUT" ]]; then
    # Case 1: specific file provided
    echo "📘 Input is a file: $INPUT"
    FILES+=("$INPUT")
elif [[ -d "$INPUT" ]]; then
    # Case 2: input is a directory
    echo "📂 Input is a directory: $INPUT"
    while IFS= read -r f; do FILES+=("$f"); done < <(ls "$INPUT"/*raw_dataset*.jsonl 2>/dev/null || true)

    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "❌ No *raw_dataset*.jsonl files found in directory: $INPUT"
        exit 1
    fi
else
    echo "❌ Invalid path: $INPUT"
    exit 1
fi


########################################
# Process all matched files
########################################
for RAW_FILE in "${FILES[@]}"; do
    echo "filename: $RAW_FILE"

    LINE=$(head -n 1 "$RAW_FILE")
    LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')
    LANG_RAW=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')

    echo "🔍 Detected language: $LANG_RAW"
    # if [ -z "$LANG_RAW" ]; then
    #     LANG_RAW="java"
    # fi
    # if [ "$LANG_RAW" == "Go" ]; then
    #     LANG_RAW="golang"
    # fi
    GEN_INSTANCE="$SCRIPT_DIR/../data_pipeline/gen_instance_from_dataset_${LANG_RAW}.sh"
    echo " Using GEN_INSTANCE: $GEN_INSTANCE"
    chmod +x "$GEN_INSTANCE"
    # FILENAME=$(basename "$RAW_FILE")
    # DIRNAME=$(dirname "$RAW_FILE")
    # TEMP_FILE="${DIRNAME}/temp_single_${FILENAME}"

    # echo "=============================================="
    # echo "📘 Processing raw dataset: $FILENAME"
    # echo "=============================================="

    # # Extract only first line
    # echo "📌 Extracting first record → $TEMP_FILE"
    # head -n 1 "$RAW_FILE" > "$TEMP_FILE"

    # echo "🔧 Step 1: auto_add_import.sh..."
    # "$AUTO_ADD_IMPORT" "$TEMP_FILE"
    # echo ""

    # echo "📂 Step 2: create_org_dir.sh..."
    # "$CREATE_ORG_DIR" "$TEMP_FILE"
    # echo ""

    # echo "🧬 Step 3: gen_instance_from_dataset_$LANG_RAW.sh..."
    # "$GEN_INSTANCE" "$TEMP_FILE" 
    # echo ""

    # echo "🧹 Cleaning temp file: $TEMP_FILE"
    # rm -f "$TEMP_FILE"
    # echo "✔ Temp file removed."

    # echo "🎉 Finished processing: $FILENAME"
    # echo ""
done

##########################################
# Finally: Build dataset (supports multiple records)
##########################################
# echo "========================================="
# echo "🚀 Finally: Building dataset..."
# echo "========================================="

# # ---- Safe derive BASE_NAME ----
# if [ -z "${BASE_NAME-}" ]; then
#     RAW_BASENAME=$(basename "$RAW_FILE")
#     BASE_NAME="${RAW_BASENAME%%_raw_dataset.jsonl}"
# fi
# # --------------------------------

# "$SCRIPT_DIR/../data_pipeline/build_dataset.sh" "$RAW_FILE"

# ##########################################
# Derive dataset filename (multiple records merged into one file)
# ##########################################
# DATASET_FILE="${BASE_NAME}_dataset.jsonl"
# DATASET_PATH="./data/datasets/$DATASET_FILE"

# if [ ! -f "$DATASET_PATH" ]; then
#     echo "❌ Error: dataset file not generated: $DATASET_PATH"
#     exit 1
# fi

# echo "✅ Dataset generated: $DATASET_PATH"

# echo "🏁 All selected raw_dataset files processed successfully!"