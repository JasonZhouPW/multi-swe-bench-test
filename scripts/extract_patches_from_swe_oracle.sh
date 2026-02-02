#!/usr/bin/env bash

INPUT_DIR="${1:?Usage: $0 <input_directory> [output_directory]}"
OUTPUT_DIR="${2:-./extracted_diffs}"

mkdir -p "$OUTPUT_DIR"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for this script." >&2
    exit 1
fi

echo "Scanning directory: $INPUT_DIR"
shopt -s nullglob
JSONL_FILES=("$INPUT_DIR"/*.jsonl)

if [ ${#JSONL_FILES[@]} -eq 0 ]; then
    echo "No *.jsonl files found in $INPUT_DIR"
    exit 0
fi

TOTAL_PATCHES=0

for jsonl_file in "${JSONL_FILES[@]}"; do
    echo "Processing $jsonl_file ..."

    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi

        instance_id=$(echo "$line" | jq -r '.instance_id // empty')
        if [ -z "$instance_id" ] || [ "$instance_id" == "null" ]; then continue; fi

        org_repo=$(echo "$instance_id" | sed 's/-.*//')
        org=$(echo "$org_repo" | sed 's/__.*//')
        repo=$(echo "$org_repo" | sed 's/.*__//')
        pr_number=$(echo "$instance_id" | sed 's/.*-//')

        # base_commit=$(echo "$line" | jq -r '.base_commit // "unknown"')
        # if [ "$base_commit" == "null" ] || [ -z "$base_commit" ]; then
        #     base_commit="unknown"
        # fi

        patch=$(echo "$line" | jq -r '.patch // empty')
        if [ -z "$patch" ] || [ "$patch" == "null" ]; then continue; fi

        clean_patch=$(echo "$patch" | sed 's/^<patch>//' | sed 's/<\/patch>$//')

        diff_file="$OUTPUT_DIR/${org}_${repo}_${pr_number}.diff"

        echo "  Extracting patch for $org/$repo #$pr_number -> $(basename "$diff_file")"
        echo "$clean_patch" > "$diff_file"
        ((TOTAL_PATCHES++))

    done < "$jsonl_file"
done

echo ""
echo "Extraction completed."
echo "Total patches extracted: $TOTAL_PATCHES"
echo "Diffs saved to: $OUTPUT_DIR"
