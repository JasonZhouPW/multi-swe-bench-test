#!/usr/bin/env bash
# gen_all_raw_datasets.sh: Batch process gen_raw_dataset.sh for multiple languages.

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Define the language array
LANGUAGES=("Python" "Java" "Javascript" "Rust" "C" "C++" "Typescript" "Go")

echo "Starting batch raw dataset generation for languages: ${LANGUAGES[*]}"

for lang in "${LANGUAGES[@]}"; do
    echo "----------------------------------------------------"
    echo "Processing language: $lang"
    echo "----------------------------------------------------"
    
    # Call gen_raw_dataset.sh with the specified parameters
    # -l language: from array
    # -s min_stars: 10000
    # -n max_results: 200
    # -m merged_after: 2026-01-01
    bash "$SCRIPT_DIR/new_gen_raw_dataset_graphql.sh" \
        -l "$lang" \
        -s 10000 \
        -n 200 \
        -m 2025-12-15 \
        -o "$SCRIPT_DIR/data/raw_datasets/all_raw_datasets/$lang"
        
    echo "Finished processing $lang."
done

echo "Batch processing completed."
