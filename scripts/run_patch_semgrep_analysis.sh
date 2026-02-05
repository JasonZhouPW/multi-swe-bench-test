#!/usr/bin/env bash
# run_patch_semgrep_analysis.sh - Extract patches and run semgrep analysis
# Usage: ./run_patch_semgrep_analysis.sh <input_folder> <output_folder> <input_type>
#
# Parameters:
#   input_folder   - Input folder containing data files
#   output_folder  - Output folder for patches and analysis results
#   input_type     - 0: swe_oracle, 1: raw_datasets
#
# This script:
# 1. Extracts patch files from input based on input_type
#    - input_type=0: Calls extract_patches_from_swe_oracle.sh
#    - input_type=1: Calls extract_diffs.sh for raw datasets
# 2. Calls analyze_patches_batch.py to analyze patches and generate semgrep_result.csv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_FOLDER="${1:?Usage: $0 <input_folder> <output_folder> <input_type (0: swe_oracle, 1: raw_datasets)>}"
OUTPUT_FOLDER="${2:?Usage: $0 <input_folder> <output_folder> <input_type (0: swe_oracle, 1: raw_datasets)>}"
INPUT_TYPE="${3:?Usage: $0 <input_folder> <output_folder> <input_type (0: swe_oracle, 1: raw_datasets)>}"

# Validate input folder exists
if [ ! -d "$INPUT_FOLDER" ]; then
    echo "Error: Input folder '$INPUT_FOLDER' does not exist." >&2
    exit 1
fi

# Validate input_type
if [[ "$INPUT_TYPE" != "0" && "$INPUT_TYPE" != "1" ]]; then
  echo "Error: input_type must be 0 (swe_oracle) or 1 (raw_datasets)." >&2
  exit 1
fi

# Create output folder if it doesn't exist
mkdir -p "$OUTPUT_FOLDER"

PATCHES_DIR="$OUTPUT_FOLDER/patches"

if [ "$INPUT_TYPE" = "0" ]; then
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
else
  echo "=============================================="
  echo "Step 1: Extracting diffs from raw datasets"
  echo "=============================================="
  echo "Input folder: $INPUT_FOLDER"
  echo "Patches output: $PATCHES_DIR"
  echo ""

  "$SCRIPT_DIR/extract_diffs.sh" "$INPUT_FOLDER" "$PATCHES_DIR"

  if [ $? -ne 0 ]; then
    echo "Error: Failed to extract diffs." >&2
    exit 1
  fi
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
