#!/usr/bin/env bash
# batch_analyze_patches.sh: Run semgrep scan and analysis on all patches in a directory.
# Usage: ./batch_analyze_patches.sh <patch_directory> [output_file]

set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <patch_directory> [output_file]}"
RESULT_FILE="${2:-result_score.txt}"

# Ensure input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist."
    exit 1
fi

# Reset result file if it exists
> "$RESULT_FILE"

echo "Analyzing patches in '$INPUT_DIR'..."

count=0
while read -r patch_file; do
    [ -f "$patch_file" ] || continue
    
    patch_name=$(basename "$patch_file")
    tmp_json=$(mktemp -t patch_analysisXXXXXX).json
    
    echo "Processing $patch_name..."
    
    # 1. Run semgrep scan
    ./semgrep_scan.sh "$patch_file" "$tmp_json" > /dev/null 2>&1 || {
        echo "$patch_name : scan failed" >> "$RESULT_FILE"
        rm -f "$tmp_json"
        continue
    }
    
    # 2. Analyze patch and extract score
    # Final Score: 100 / 100
    analysis_output=$(./analyze_patch.sh "$tmp_json")
    score=$(echo "$analysis_output" | grep "Final Score:" | awk -F': ' '{print $2}' | awk -F' / ' '{print $1}')
    
    if [ -n "$score" ]; then
        echo "$patch_name : $score" >> "$RESULT_FILE"
    else
        echo "$patch_name : analysis failed" >> "$RESULT_FILE"
    fi
    
    rm -f "$tmp_json"
    ((count++))
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*.patch")

echo "Done. Analyzed $count patches. Results saved to '$RESULT_FILE'."
