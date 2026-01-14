#!/usr/bin/env bash
# combine_jsonl.sh: Combine all .jsonl files in a directory into one.

set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <input_directory> [output_file]}"
OUTPUT_FILE="${2:-combined.jsonl}"

# Ensure input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist."
    exit 1
fi

# Reset output file if it exists
> "$OUTPUT_FILE"

echo "Combining .jsonl files from '$INPUT_DIR' into '$OUTPUT_FILE'..."

# Find all .jsonl files and append them to the output file
# We use a loop and ensure each file ends with a newline
count=0
while read -r line; do
    cat "$line" >> "$OUTPUT_FILE"
    # Ensure there's a newline at the end of each file's content
    if [ -n "$(tail -c 1 "$OUTPUT_FILE")" ]; then
        echo "" >> "$OUTPUT_FILE"
    fi
    ((count++))
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*.jsonl")

# Cleanup empty lines in output if any (cat might add extra newlines)
sed -i '' '/^[[:space:]]*$/d' "$OUTPUT_FILE"

echo "Done. Combined $count files into '$OUTPUT_FILE'."
