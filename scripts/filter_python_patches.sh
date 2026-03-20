#!/bin/bash

# Filter Python code patches from JSONL file
# - Filter records where fix_patch contains .py file modifications
# - Filter records where Python code changes > 100 bytes
# - Output to files with max 25MB each

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Input and output
INPUT_FILE="${1:-$PROJ_ROOT/raw_datasets/py/python_rds.jsonl}"
OUTPUT_DIR="${2:-$PROJ_ROOT/raw_datasets/py/filtered}"

# Max file size in bytes (25MB)
MAX_FILE_SIZE=$((25 * 1024 * 1024))

# Min Python code size in bytes
MIN_PYTHON_SIZE=100

mkdir -p "$OUTPUT_DIR"

echo -e "${GREEN}Starting Python patch filter...${NC}"
echo -e "Input file: ${INPUT_FILE}"
echo -e "Output directory: ${OUTPUT_DIR}"
echo -e "Min Python code size: ${MIN_PYTHON_SIZE} bytes"
echo -e "Max file size: 25MB"
echo ""

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Function to calculate Python code size from a patch
# Only counts lines that modify .py files
calculate_python_code_size() {
    local patch="$1"
    echo "$patch" | awk '
    BEGIN {
        in_py = 0
        hunk_size = 0
        total = 0
    }
    /^diff --git / {
        split($0, parts, " ")
        filepath = parts[3]
        sub(/^a\//, "", filepath)

        # Check if it is a Python file
        is_py = 0
        if (filepath ~ /\.py$/) {
            is_py = 1
        }

        if (in_py == 1 && hunk_size > 0) total += hunk_size
        in_py = is_py
        hunk_size = 0
    }
    /^@@/ {
        if (in_py == 1 && hunk_size > 0) total += hunk_size
        hunk_size = 0
    }
    /^[+-]/ {
        if (in_py == 1) hunk_size += length($0) - 1
    }
    END {
        if (in_py == 1 && hunk_size > 0) total += hunk_size
        print total
    }
    '
}

# Function to check if patch contains Python file modifications
contains_python_files() {
    local patch="$1"
    echo "$patch" | grep -q "^diff --git .*/.*\.py " && echo "yes" || echo "no"
}

# Process the file
total_records=0
filtered_records=0
file_index=1
current_size=0

OUTPUT_FILE="${OUTPUT_DIR}/python_filtered_part${file_index}.jsonl"
echo "" > "$OUTPUT_FILE"

echo -e "${YELLOW}Processing records...${NC}"

while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
        continue
    fi

    total_records=$((total_records + 1))

    # Extract fix_patch
    fix_patch=$(echo "$line" | jq -r '.fix_patch // empty')

    if [ -z "$fix_patch" ] || [ "$fix_patch" = "null" ]; then
        continue
    fi

    # Check if contains Python file modifications
    has_py=$(contains_python_files "$fix_patch")
    if [ "$has_py" != "yes" ]; then
        continue
    fi

    # Calculate Python code size
    py_size=$(calculate_python_code_size "$fix_patch")

    if [ "$py_size" -lt "$MIN_PYTHON_SIZE" ]; then
        continue
    fi

    # Get line size
    line_size=${#line}

    # Check if we need to start a new file
    if [ $((current_size + line_size)) -gt $MAX_FILE_SIZE ]; then
        echo -e "${GREEN}File ${file_index} created: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')${NC}"
        file_index=$((file_index + 1))
        OUTPUT_FILE="${OUTPUT_DIR}/python_filtered_part${file_index}.jsonl"
        echo "" > "$OUTPUT_FILE"
        current_size=0
    fi

    # Write the line
    echo "$line" >> "$OUTPUT_FILE"
    current_size=$((current_size + line_size))
    filtered_records=$((filtered_records + 1))

    if [ $((filtered_records % 100)) -eq 0 ]; then
        echo -e "Filtered ${filtered_records} records..."
    fi

done < "$INPUT_FILE"

echo ""
echo -e "${GREEN}Filtering completed!${NC}"
echo -e "Total records processed: ${total_records}"
echo -e "Filtered records: ${filtered_records}"
echo -e "Output files created: ${file_index}"
echo ""
echo -e "${YELLOW}Output files:${NC}"
ls -lh "$OUTPUT_DIR"/python_filtered_part*.jsonl 2>/dev/null || echo "No output files created"