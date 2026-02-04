#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# Merge JSONL Files by Subdirectory
# ================================================================
#
# Usage: ./merge_jsonl_by_subdir.sh <input_directory>
#
# This script:
# 1. Takes a directory path as parameter
# 2. Finds all subdirectories
# 3. Merges all .jsonl files in each subdirectory into one file
# 4. Names output file as: filtered_YYYYMMDD_<subdir_name>.jsonl
#
# Example:
#   ./merge_jsonl_by_subdir.sh ./raw_datasets/filtered
#
#   Output:
#     - filtered_20260204_bug-fix.jsonl
#     - filtered_20260204_edge.jsonl
#     - filtered_20260204_performance.jsonl
#     - filtered_20260204_refactor.jsonl
#
# ================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if directory argument is provided
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Missing required argument.${NC}"
    echo ""
    echo "Usage: $0 <input_directory>"
    echo ""
    echo "Example:"
    echo "  $0 ./raw_datasets/filtered"
    exit 1
fi

INPUT_DIR="$1"

# Verify input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo -e "${RED}Error: Directory does not exist: $INPUT_DIR${NC}"
    exit 1
fi

# Get absolute path
INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"

# Get current date in YYYYMMDD format
CURRENT_DATE=$(date +%Y%m%d)

# Counters
TOTAL_SUBDIRS=0
TOTAL_FILES_MERGED=0
TOTAL_OUTPUT_FILES=0

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}        Merge JSONL Files by Subdirectory                        ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Input Directory: ${YELLOW}$INPUT_DIR${NC}"
echo -e "Output Prefix:   ${YELLOW}filtered_${CURRENT_DATE}_${NC}"
echo -e "Output Suffix:   ${YELLOW}.jsonl${NC}"
echo ""

# Function to merge JSONL files in a subdirectory
merge_jsonl_files() {
    local subdir="$1"
    local subdir_name=$(basename "$subdir")
    local output_file="$INPUT_DIR/filtered_${CURRENT_DATE}_${subdir_name}.jsonl"

    # Find all .jsonl files in the subdirectory
    local jsonl_files
    jsonl_files=$(find "$subdir" -maxdepth 1 -type f -name "*.jsonl" | sort)

    local file_count=$(echo "$jsonl_files" | grep -c . || echo "0")

    if [ "$file_count" -eq 0 ]; then
        echo -e "${YELLOW}  [SKIP] ${subdir_name}: No .jsonl files found${NC}"
        return 1
    fi

    echo -e "${GREEN}  [MERGE] ${subdir_name}: ${file_count} file(s)${NC}"

    # Merge all jsonl files
    # Using cat to concatenate files
    cat $jsonl_files > "$output_file"

    local merged_lines=0
    if [ -f "$output_file" ]; then
        merged_lines=$(wc -l < "$output_file" | tr -d ' ')
    fi

    echo -e "    Output: ${CYAN}${output_file}${NC}"
    echo -e "    Lines:  ${YELLOW}${merged_lines}${NC}"

    TOTAL_FILES_MERGED=$((TOTAL_FILES_MERGED + file_count))
    TOTAL_OUTPUT_FILES=$((TOTAL_OUTPUT_FILES + 1))

    return 0
}

# Find all subdirectories in the input directory
SUBDIRS=$(find "$INPUT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

TOTAL_SUBDIRS=$(echo "$SUBDIRS" | grep -c . || echo "0")

if [ "$TOTAL_SUBDIRS" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No subdirectories found in $INPUT_DIR${NC}"
    exit 0
fi

echo -e "${CYAN}Found ${TOTAL_SUBDIRS} subdirectory(s) to process${NC}"
echo ""

# Process each subdirectory
for subdir in $SUBDIRS; do
    merge_jsonl_files "$subdir"
done

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}Merge Complete!${NC}"
echo -e "================================================================${NC}"
echo -e "Subdirectories processed: ${YELLOW}${TOTAL_SUBDIRS}${NC}"
echo -e "JSONL files merged:    ${YELLOW}${TOTAL_FILES_MERGED}${NC}"
echo -e "Output files created:  ${YELLOW}${TOTAL_OUTPUT_FILES}${NC}"
echo -e "Output directory:      ${YELLOW}${INPUT_DIR}${NC}"
echo ""
