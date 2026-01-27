#!/usr/bin/env bash
# extract_patches.sh - Extract fix_patch from raw dataset files
# Usage: ./extract_patches.sh <input_directory> [output_directory]

set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <input_directory> [output_directory]}"
OUTPUT_DIR="${2:-./extracted_patches}"

mkdir -p "$OUTPUT_DIR"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for this script." >&2
    exit 1
fi

echo "Scanning directory: $INPUT_DIR"
shopt -s nullglob
RAW_FILES=("$INPUT_DIR"/*_raw_dataset.jsonl)

if [ ${#RAW_FILES[@]} -eq 0 ]; then
    echo "No *_raw_dataset.jsonl files found in $INPUT_DIR"
    exit 0
fi

for jsonl_file in "${RAW_FILES[@]}"; do
    echo "Processing $jsonl_file ..."
    
    # Extract each line and save to separate patch file
    # Filename format: <org>_<repo>_<number>.patch
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        # Check if it has fix_patch and it is not null
        has_patch=$(echo "$line" | jq -r 'if has("fix_patch") and .fix_patch != null then "true" else "false" end')
        if [ "$has_patch" != "true" ]; then continue; fi
        
        org=$(echo "$line" | jq -r '.org // "unknown"')
        repo=$(echo "$line" | jq -r '.repo // "unknown"')
        number=$(echo "$line" | jq -r '.number // "0"')
        
        patch_file="$OUTPUT_DIR/${org}_${repo}_${number}.patch"
        
        echo "  Extracting patch for $org/$repo #$number -> $(basename "$patch_file")"
        echo "$line" | jq -r '.fix_patch' > "$patch_file"
        
    done < "$jsonl_file"
done

echo "Extraction completed. Patches saved to $OUTPUT_DIR"
