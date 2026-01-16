#!/usr/bin/env bash
# gen_raw_dataset_from_prs.sh: Generate raw_dataset from a list of PR URLs.
# Usage: ./gen_raw_dataset_from_prs.sh <urls_file> <output_dir>

set -euo pipefail

URLS_FILE="${1:?Usage: $0 <urls_file> <output_dir>}"
OUT_DIR="${2:?Usage: $0 <urls_file> <output_dir>}"
TOKEN_FILE="./tokens.txt"

# 1. Fetch PR details
echo "=== Step 1: Fetching PR details from URLs ==="
python3 -m multi_swe_bench.collect.get_prs_by_urls \
    --urls_file "$URLS_FILE" \
    --out_dir "$OUT_DIR" \
    --tokens "$TOKEN_FILE"

# 2. Iterate over generated JSONL files and run pipeline
shopt -s nullglob
PRS_FILES=("$OUT_DIR"/*_prs.jsonl)

for prs_jsonl in "${PRS_FILES[@]}"; do
    # Skip already filtered files etc.
    if [[ "$prs_jsonl" == *"_filtered_prs"* ]]; then continue; fi
    
    filename=$(basename "$prs_jsonl")
    # Expected format: org__repo_prs.jsonl
    repo_key=${filename%_prs.jsonl}
    org=$(echo "$repo_key" | awk -F'__' '{print $1}')
    repo=$(echo "$repo_key" | awk -F'__' '{print $2}')
    
    echo "=== Processing Pipeline for $org/$repo ==="
    
    # Step 2: Filter PRs
    echo "--- Step 2: Filtering PRs ---"
    python3 -m multi_swe_bench.collect.filter_prs \
        --tokens "$TOKEN_FILE" \
        --out_dir "$OUT_DIR" \
        --prs_file "$prs_jsonl" \
        --skip-commit-message False

    # Step 3: Fetch related issues
    echo "--- Step 3: Fetching related issues ---"
    filtered_file="$OUT_DIR/${repo_key}_filtered_prs.jsonl"
    python3 -m multi_swe_bench.collect.get_related_issues \
        --tokens "$TOKEN_FILE" \
        --out_dir "$OUT_DIR" \
        --filtered_prs_file "$filtered_file"

    # Step 4: Merge PRs + Issues
    echo "--- Step 4: Merging PRs and Issues ---"
    python3 -m multi_swe_bench.collect.merge_prs_with_issues \
        --out_dir "$OUT_DIR" \
        --org "$org" \
        --repo "$repo"

    # Step 5: Build Dataset
    echo "--- Step 5: Building Dataset ---"
    merged_file="$OUT_DIR/${repo_key}_filtered_prs_with_issues.jsonl"
    python3 -m multi_swe_bench.collect.build_dataset \
        --tokens "$TOKEN_FILE" \
        --out_dir "$OUT_DIR" \
        --filtered-prs-with-issues-file "$merged_file" \
        --delay-on-error 300 \
        --retry-attempts 3

done

echo "=== All PRs processed! ==="
