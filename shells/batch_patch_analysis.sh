#!/usr/bin/env bash
# batch_patch_analysis.sh: Run semgrep scan and analysis on all patches in a directory and save results to CSV.
# Usage: ./batch_patch_analysis.sh <patch_directory> [output_csv]

set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <patch_directory> [output_csv]}"
OUTPUT_CSV="${2:-patch_result.csv}"

# Ensure input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist."
    exit 1
fi

# Initialize CSV with layout
echo "patch file name,score,grade" > "$OUTPUT_CSV"

echo "Analyzing patches in '$INPUT_DIR'..."

count=0
# Loop through all .patch files in the input directory
while IFS= read -r patch_file; do
    [ -f "$patch_file" ] || continue
    
    patch_name=$(basename "$patch_file")
    tmp_json=$(mktemp -t patch_analysisXXXXXX).json
    
    echo "Processing $patch_name..."
    
    # 1. Run semgrep scan
    # Redirect stdout to /dev/null to keep it clean, but keep stderr for errors
    if ! ./semgrep_scan.sh "$patch_file" "$tmp_json" > /dev/null 2>&1; then
        echo "scan failed fro $patch_file"
        echo "$patch_name,NA,SCAN_FAILED" >> "$OUTPUT_CSV"
        rm -f "$tmp_json"
        continue
    fi
    echo "2222"
    
    # 2. Analyze patch and extract score and grade
    # analyze_patch.sh output example:
    # Final Score: 100 / 100
    # Patch Grade: S (Excellent)
    analysis_output=$(./analyze_patch.sh "$tmp_json")

    echo "output of $  patch_file: $analysis_output"
    
    score=$(echo "$analysis_output" | grep "Final Score:" | awk -F': ' '{print $2}' | awk -F' / ' '{print $1}' | tr -d ' ')
    grade=$(echo "$analysis_output" | grep "Patch Grade:" | awk -F': ' '{print $2}' | xargs)
    
    if [ -n "$score" ] && [ -n "$grade" ]; then
        echo "$patch_name,$score,$grade" >> "$OUTPUT_CSV"
    else
        echo "$patch_name,NA,ANALYSIS_FAILED" >> "$OUTPUT_CSV"
    fi
    
    # Cleanup
    rm -f "$tmp_json"
    ((count++))
# Use process substitution for portable reading of find output
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*.patch")

echo "Done. Analyzed $count patches. Results saved to '$OUTPUT_CSV'."
