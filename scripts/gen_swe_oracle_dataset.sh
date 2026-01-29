#!/bin/bash

# Script to generate dataset.jsonl from raw JSONL files
# Usage: ./gen_swe_oracle_dataset.sh <input_directory> <output_file>
# Example: ./gen_swe_oracle_dataset.sh ./data/raw_datasets swe_oracle_dataset.jsonl

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# GitHub API configuration
API_KEY="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"
API_BASE="https://api.github.com"

# Check parameters
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Missing required parameters.${NC}"
    echo -e "Usage: $0 <input_directory> <output_file>"
    exit 1
fi

# Paths
INPUT_DIR="$1"
OUTPUT_FILE="$2"

echo -e "${GREEN}Starting dataset generation...${NC}"
echo -e "Input directory: ${INPUT_DIR}"
echo -e "Output file: ${OUTPUT_FILE}"
echo ""

# Check if input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo -e "${RED}Error: Input directory not found: $INPUT_DIR${NC}"
    exit 1
fi

# Collect all JSONL files to process
echo -e "${YELLOW}Finding JSONL files in: ${INPUT_DIR}${NC}"
files_to_process=()
while IFS= read -r -d '' jsonl_file; do
    files_to_process+=("$jsonl_file")
done < <(find "$INPUT_DIR" -name "*.jsonl" -type f -print0)

if [ ${#files_to_process[@]} -eq 0 ]; then
    echo -e "${RED}Error: No .jsonl files found in directory: $INPUT_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Found ${#files_to_process[@]} JSONL file(s)${NC}"
echo ""

# Clear output file
> "$OUTPUT_FILE"

# Global counters
total_processed=0
total_files=0

fetch_hints_text() {
    local comments_url="$1"

    if [ -z "$comments_url" ] || [ "$comments_url" = "null" ]; then
        echo ""
        return
    fi

    local hints_text=""
    local retry_count=0
    local max_retries=5

        while [ $retry_count -lt $max_retries ]; do
            local page=1
            local per_page=100
            local has_more=true

            while [ "$has_more" = true ]; do
                local http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${API_KEY}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "${comments_url}?page=${page}&per_page=${per_page}")

                if [ "$http_code" = "404" ]; then
                    break 2
                fi

                if [ "$http_code" = "429" ]; then
                    local wait_time=$(( (retry_count + 1) * 10 ))
                    echo -e "${YELLOW}Rate limit hit. Waiting ${wait_time}s before retry...${NC}"
                    sleep $wait_time
                    retry_count=$((retry_count + 1))
                    break
                fi

                local response=$(curl -s -H "Authorization: Bearer ${API_KEY}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "${comments_url}?page=${page}&per_page=${per_page}")

                local messages=$(echo "$response" | jq -r '.[] | .body' 2>/dev/null | while read -r msg; do
                    [ -n "$msg" ] && [ "$msg" != "null" ] && echo "$msg"
                done | paste -sd '\n\n' -)

            if [ -n "$messages" ]; then
                if [ -n "$hints_text" ]; then
                    hints_text="${hints_text}\n\n${messages}"
                else
                    hints_text="$messages"
                fi
            fi

            if echo "$response" | jq -e 'length >= '"$per_page"'' > /dev/null 2>&1; then
                page=$((page + 1))
            else
                has_more=false
            fi
        done

        # If we successfully completed pagination, break the retry loop
        if [ "$has_more" = false ] || [ $retry_count -ge $((max_retries - 1)) ]; then
            break
        fi
    done

    echo "$hints_text"
}

# Function to process a single JSONL file
process_file() {
    local input_file="$1"
    local output_file="$2"

    echo -e "${YELLOW}Processing file: ${input_file}${NC}"

    # Check if input file exists
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Input file not found: $input_file${NC}"
        return 1
    fi

    # Counter for this file
    count=0

    # Process each line in the JSONL file
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            continue
        fi

        # Extract fields using jq
        org=$(echo "$line" | jq -r '.org')
        repo=$(echo "$line" | jq -r '.repo')
        number=$(echo "$line" | jq -r '.number')
        base_commit_hash=$(echo "$line" | jq -r '.base_commit_hash')
        created_at=$(echo "$line" | jq -r '.created_at')
        fix_patch=$(echo "$line" | jq -r '.fix_patch')
        title=$(echo "$line" | jq -r '.title')
        body=$(echo "$line" | jq -r '.body')
        pr_url=$(echo "$line" | jq -r '.url')
        comments_url=$(echo "$line" | jq -r '.comments_url')

        # Skip if required fields are missing
        if [ "$org" = "null" ] || [ "$repo" = "null" ] || [ "$number" = "null" ]; then
            echo -e "${YELLOW}Skipping entry: Missing required fields (org/repo/number)${NC}"
            continue
        fi

        # Skip if fix_patch is null or empty
        if [ "$fix_patch" = "null" ] || [ -z "$fix_patch" ]; then
            echo -e "${YELLOW}Skipping PR ${org}/${repo}#${number}: No fix_patch available${NC}"
            continue
        fi

        # Construct instance_id
        instance_id="${org}__${repo}-${number}"

        # Get problem_statement from resolved_issues or use title/body
        resolved_issues_count=$(echo "$line" | jq '.resolved_issues | length')

        if [ "$resolved_issues_count" -gt 0 ]; then
            # Concatenate all resolved_issues' title and body
            problem_statement=""
            for ((i=0; i<resolved_issues_count; i++)); do
                issue_title=$(echo "$line" | jq -r ".resolved_issues[$i].title")
                issue_body=$(echo "$line" | jq -r ".resolved_issues[$i].body")

                if [ "$issue_title" != "null" ] && [ -n "$issue_title" ]; then
                    if [ -n "$problem_statement" ]; then
                        problem_statement="${problem_statement}\n\n## ${issue_title}\n${issue_body}"
                    else
                        problem_statement="## ${issue_title}\n${issue_body}"
                    fi
                fi
            done
        else
            # Use current PR's title and body
            problem_statement="## ${title}\n${body}"
        fi

        echo -e "${YELLOW}Fetching hints for ${org}/${repo}#${number}...${NC}"
        hints_text=$(fetch_hints_text "$comments_url")

        patch_content="<patch>\n${fix_patch}\n</patch>"

        temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" EXIT

        printf '%s' "$instance_id" > "${temp_dir}/INSTANCE_ID"
        printf '%s' "${org}/${repo}" > "${temp_dir}/REPO"
        printf '%s' "$base_commit_hash" > "${temp_dir}/BASE_COMMIT"
        printf '%s' "$problem_statement" > "${temp_dir}/PROBLEM_STATEMENT"
        printf '%s' "$hints_text" > "${temp_dir}/HINTS_TEXT"
        printf '%s' "$created_at" > "${temp_dir}/CREATED_AT"
        printf '%s' "$patch_content" > "${temp_dir}/PATCH"

        export INSTANCE_ID_FILE="${temp_dir}/INSTANCE_ID"
        export REPO_FILE="${temp_dir}/REPO"
        export BASE_COMMIT_FILE="${temp_dir}/BASE_COMMIT"
        export PROBLEM_STATEMENT_FILE="${temp_dir}/PROBLEM_STATEMENT"
        export HINTS_TEXT_FILE="${temp_dir}/HINTS_TEXT"
        export CREATED_AT_FILE="${temp_dir}/CREATED_AT"
        export PATCH_FILE="${temp_dir}/PATCH"

        python3 "${SCRIPT_DIR}/build_entry.py" >> "$output_file"
        echo "" >> "$output_file"

        rm -rf "$temp_dir"

        count=$((count + 1))
        total_processed=$((total_processed + 1))

        if [ $((count % 10)) -eq 0 ]; then
            echo -e "Processed ${count} entries from this file..."
        fi

    done < "$input_file"

    echo -e "${GREEN}Completed processing ${input_file}!${NC}"
    echo -e "Entries from this file: ${count}"
    echo ""
    total_files=$((total_files + 1))
}

# Process all files
for jsonl_file in "${files_to_process[@]}"; do
    process_file "$jsonl_file" "$OUTPUT_FILE"
done

echo -e "${GREEN}All processing completed!${NC}"
echo -e "Total files processed: ${total_files}"
echo -e "Total entries processed: ${total_processed}"
echo -e "Output file: ${OUTPUT_FILE}"
echo ""
echo -e "${YELLOW}Dataset generation complete!${NC}"
