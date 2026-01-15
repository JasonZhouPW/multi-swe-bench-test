#!/usr/bin/env bash
# gen_all_raw_datasets.sh: Batch process gen_raw_dataset.sh for multiple languages.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Define the language array
LANGUAGES=( "Python" "Javascript" "Rust" "C" "Typescript" "Rust")

echo "Starting batch raw dataset generation for languages: ${LANGUAGES[*]}"

for lang in "${LANGUAGES[@]}"; do
    echo "----------------------------------------------------"
    echo "Processing language: $lang"
    echo "----------------------------------------------------"
    
    # Call gen_raw_dataset.sh with the specified parameters
    # -l language: from array
    # -s min_stars: 10000
    # -n max_results: 200
    # -c created_at: 2025-10-15
    bash "$SCRIPT_DIR/gen_raw_dataset.sh" \
        -l "$lang" \
        -s 10000 \
        -n 200 \
        -c 2025-10-15
        
    echo "Finished processing $lang."
done

echo "Batch processing completed."
