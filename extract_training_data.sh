#!/bin/bash

# Script to extract training data from JSONL files
# Usage: ./extract_training_data.sh [input_path] [output_file]
# If input_path is a file: process that file
# If input_path is a directory: process all .jsonl files in that directory
# All data is merged into a single output file
# Output format matches training_template.json structure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_INPUT="${SCRIPT_DIR}/sample_raw_dataset.json"
DEFAULT_OUTPUT="${SCRIPT_DIR}/training_dataset.json"

# Get arguments
INPUT_PATH="${1:-$DEFAULT_INPUT}"
OUTPUT_FILE="${2:-$DEFAULT_OUTPUT}"

# Question for reverse training data
QUESTION="What design or code quality issue does this patch address?"

echo -e "${GREEN}Starting training data extraction...${NC}"
echo -e "Input path: ${INPUT_PATH}"
echo -e "Output file: ${OUTPUT_FILE}"
echo ""

# Check if input path exists
if [ ! -e "$INPUT_PATH" ]; then
    echo -e "${RED}Error: Input path not found: $INPUT_PATH${NC}"
    exit 1
fi

# Global counter for all processed entries
total_processed=0

# Function to process a single JSONL file and append to output
process_file() {
    local input_file="$1"
    local output_file="$2"
    local is_first_file="$3"  # true if this is the first file being processed

    echo -e "${YELLOW}Processing file: ${input_file}${NC}"

    # Check if input file exists (double check)
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Input file not found: $input_file${NC}"
        return 1
    fi

    # Process JSONL file and convert to training format
    echo -e "${YELLOW}Processing data...${NC}"

    # Counter for this file
    count=0

    # Process each line in the JSONL file
    first=true
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            continue
        fi

        # Extract fields using jq
        org=$(echo "$line" | jq -r '.org')
        repo=$(echo "$line" | jq -r '.repo')
        number=$(echo "$line" | jq -r '.number')
        title=$(echo "$line" | jq -r '.title')
        body=$(echo "$line" | jq -r '.body')
        fix_patch=$(echo "$line" | jq -r '.fix_patch')

        # Skip if fix_patch is null or empty
        if [ "$fix_patch" = "null" ] || [ -z "$fix_patch" ]; then
            echo -e "${YELLOW}Skipping PR #$number: No fix_patch available${NC}"
            continue
        fi

        # Construct user content (GitHub link + title + body)
        github_link="https://github.com/${org}/${repo}/pull/${number}"
        user_content="<github link>${github_link}</github link>\n\n<title>${title}</title>\n\n<description>${body}</description>"

        # Escape content for JSON
        user_content_escaped=$(echo "$user_content" | jq -Rs .)
        fix_patch_escaped=$(echo "$fix_patch" | jq -Rs .)

        # Handle JSON array structure
        if [ "$is_first_file" = true ] && [ "$first" = true ]; then
            # First file, first entry: start the array
            echo "[" > "$output_file"
        else
            # Add comma separator
            echo "," >> "$output_file"
        fi
        # Construct reverse user content (Patch + Question)
        reverse_user_content="Patch:\n${fix_patch}\n\nQuestion:\n${QUESTION}"
        reverse_user_content_escaped=$(echo "$reverse_user_content" | jq -Rs .)
        



        # Write training entry
        cat >> "$output_file" << EOF
    {
        "messages": [
            { "role": "system", "content": "You are a senior software engineer specializing in code refactoring." },
            {"role": "user", "content": ${user_content_escaped}},
            {"role": "assistant", "content": ${fix_patch_escaped}}
        ]
    },{
        "messages": [
            { "role": "system", "content": "You are a senior software engineer specializing in code refactoring." },
            {"role": "user", "content": ${reverse_user_content_escaped}},
            {"role": "assistant", "content": ${user_content_escaped}}
        ]
    }
EOF

        first=false
        count=$((count + 1))
        total_processed=$((total_processed + 1))

        if [ $((count % 10)) -eq 0 ]; then
            echo -e "Processed ${count} entries from this file..."
        fi

    done < "$input_file"

    echo -e "${GREEN}Completed processing ${input_file}!${NC}"
    echo -e "Entries from this file: ${count}"
    echo ""
}

# Collect all files to process
files_to_process=()

if [ -f "$INPUT_PATH" ]; then
    # Single file processing
    if [[ "$INPUT_PATH" == *.jsonl ]]; then
        files_to_process=("$INPUT_PATH")
    else
        echo -e "${RED}Error: Input file must be a .jsonl file${NC}"
        exit 1
    fi
elif [ -d "$INPUT_PATH" ]; then
    # Directory processing - find all .jsonl files
    echo -e "${YELLOW}Processing directory: ${INPUT_PATH}${NC}"
    while IFS= read -r -d '' jsonl_file; do
        files_to_process+=("$jsonl_file")
    done < <(find "$INPUT_PATH" -name "*.jsonl" -type f -print0)

    if [ ${#files_to_process[@]} -eq 0 ]; then
        echo -e "${RED}Error: No .jsonl files found in directory: $INPUT_PATH${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: Input path is neither a file nor a directory: $INPUT_PATH${NC}"
    exit 1
fi

# Process all files and merge into single output
echo -e "${YELLOW}Will process ${#files_to_process[@]} file(s) and merge into: ${OUTPUT_FILE}${NC}"

is_first_file=true
for jsonl_file in "${files_to_process[@]}"; do
    process_file "$jsonl_file" "$OUTPUT_FILE" "$is_first_file"
    is_first_file=false
done

# Close the JSON array if we processed any files
if [ $total_processed -gt 0 ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "]" >> "$OUTPUT_FILE"
fi

echo -e "${GREEN}All processing completed!${NC}"
echo -e "Total entries processed: ${total_processed}"
echo -e "Output file: ${OUTPUT_FILE}"
echo ""
echo -e "${YELLOW}You can now use the training data for model training.${NC}"
