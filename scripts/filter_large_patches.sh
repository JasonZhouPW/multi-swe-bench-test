#!/usr/bin/env bash
set -euo pipefail

# Function to calculate code-only patch size (excluding documentation files)
calculate_code_patch_size() {
    local patch="$1"
    local code_size=0

    # Documentation file extensions to exclude
    local doc_extensions=".md .txt .rst .adoc .asciidoc .readme README CHANGELOG CONTRIBUTING LICENSE NOTICE AUTHORS .gitignore .dockerignore"

    # Split patch into hunks based on diff headers
    echo "$patch" | awk -v doc_exts="$doc_extensions" '
    BEGIN {
        in_doc = 0
        hunk_size = 0
        total = 0
        split(doc_exts, exts, " ")
        for (i in exts) {
            doc_map[exts[i]] = 1
        }
    }
    /^diff --git / {
        # Extract filename from diff --git a/path b/path
        split($0, parts, " ")
        filepath = parts[3]
        sub(/^a\//, "", filepath)

        # Check if this is a documentation file
        is_doc = 0
        for (ext in doc_map) {
            if (filepath ~ ext "$") {
                is_doc = 1
                break
            }
        }
        if (tolower(filepath) ~ /readme|changelog|contributing|license|notice|authors|\.gitignore|\.dockerignore/) {
            is_doc = 1
        }

        if (in_doc == 0 && hunk_size > 0) {
            total += hunk_size
        }
        in_doc = is_doc
        hunk_size = 0
    }
    /^@@/ {
        # Start of hunk
        if (in_doc == 0 && hunk_size > 0) {
            total += hunk_size
        }
        hunk_size = 0
    }
    /^[+-]/ {
        # Count added/removed lines (excluding the +/- prefix)
        if (in_doc == 0) {
            hunk_size += length($0) - 1  # -1 for the +/- prefix
        }
    }
    END {
        if (in_doc == 0 && hunk_size > 0) {
            total += hunk_size
        }
        print total
    }
    '
}

# Usage: $0 <input_dir> <output_file> [min_patch_size]
# Default: input_dir=java_ds, output_file=$output/filtered_patch_size_raw_dataset.jsonl, min_patch_size=1024

INPUT_DIR="${1:-java_ds}"
OUTPUT_FILE="${2:-$output/filtered_patch_size_raw_dataset.jsonl}"
MIN_PATCH_SIZE="${3:-1024}"

# Create output directory if it doesn't exist
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

# Clear output file
: > "$OUTPUT_FILE"

echo "Filtering raw_dataset.jsonl files in $INPUT_DIR"
echo "Minimum patch size: $MIN_PATCH_SIZE bytes"
echo "Output: $OUTPUT_FILE"

# Find all .jsonl files in input directory
find "$INPUT_DIR" -name "*.jsonl" -type f | while IFS= read -r file; do
    echo "Processing $file"
    
    # Process each line in the JSONL file
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue
        
        # Extract fix_patch field and calculate code-only size
        patch_content=$(echo "$line" | jq -r '.fix_patch // empty')
        if [ -n "$patch_content" ]; then
            # Calculate byte size of code changes only (excluding documentation)
            code_patch_size=$(calculate_code_patch_size "$patch_content")

            # If code patch size is greater than minimum, write to output
            if [ "$code_patch_size" -gt "$MIN_PATCH_SIZE" ]; then
                echo "$line" >> "$OUTPUT_FILE"
            fi
        fi
    done < "$file"
done

echo "Filtering complete. Output written to $OUTPUT_FILE"
echo "Total filtered records: $(wc -l < "$OUTPUT_FILE")"