#!/usr/bin/env bash
# run_patch_semgrep_analysis.sh - Extract patches and run semgrep analysis
# Usage: ./run_patch_semgrep_analysis.sh <input_folder> <output_folder>
#
# This script:
# 1. Calls extract_patches_from_swe_oracle.sh to extract patch files from JSONL to output_folder/patches
# 2. Calls analyze_patches_batch.py to analyze patches and generate semgrep_result.csv in output_folder/patches

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_FOLDER="${1:?Usage: $0 <input_folder> <output_folder>}"
OUTPUT_FOLDER="${2:?Usage: $0 <input_folder> <output_folder>}"

# Validate input folder exists
if [ ! -d "$INPUT_FOLDER" ]; then
    echo "Error: Input folder '$INPUT_FOLDER' does not exist." >&2
    exit 1
fi

# Create output folder if it doesn't exist
mkdir -p "$OUTPUT_FOLDER"

PATCHES_DIR="$OUTPUT_FOLDER/patches"

echo "=============================================="
echo "Step 1: Extracting patches from SWE Oracle"
echo "=============================================="
echo "Input folder: $INPUT_FOLDER"
echo "Patches output: $PATCHES_DIR"
echo ""

"$SCRIPT_DIR/extract_patches_from_swe_oracle.sh" "$INPUT_FOLDER" "$PATCHES_DIR"

if [ $? -ne 0 ]; then
    echo "Error: Failed to extract patches." >&2
    exit 1
fi

echo ""
echo "=============================================="
echo "Step 2: Running Semgrep analysis"
echo "=============================================="
echo "Patches directory: $PATCHES_DIR"
echo ""

python3 "$SCRIPT_DIR/analyze_patches_batch.py" "$PATCHES_DIR"

if [ $? -ne 0 ]; then
    echo "Error: Semgrep analysis failed." >&2
    exit 1
fi

echo ""
echo "=============================================="
echo "Pipeline completed successfully!"
echo "=============================================="
echo "Patches extracted to: $PATCHES_DIR"
echo "Semgrep results: $PATCHES_DIR/semgrep_result.csv"
