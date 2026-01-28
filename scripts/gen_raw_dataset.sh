#!/bin/bash
set -e  # Exit on error

# Parameter configuration (overridable via CLI)
# Default values (use -o/-l/-s/-n/-t to override)
# OUTPUT_DIR="data/raw_datasets/catchorg__Catch6"
LANGUAGE="Go"
MIN_STARS=100000
MAX_RESULTS=200
TOKEN="./tokens.txt"  # Default token file path or token string
PERCENTAGE=80.0
# Other default parameters (usually no need to modify)
MAX_WORKERS=50
DISTRIBUTE="round"
DELAY_ON_ERROR=600
RETRY_ATTEMPTS=8
# Use today's date (YYYY-MM-DD) as default CREATED_AT, overridable via script or environment variables
CREATED_AT="2025-01-01" # default value
TODAY="$(date '+%Y-%m-%d')"

KEY_WORDS=""
OUTPUT_DIR=""


# Usage/help
usage() {
    echo "Usage: $0 [-o output_dir] [-l language] [-s min_stars] [-n max_results] [-t token] [-e exclude_repos]"
    echo "  -o output_dir    Output directory for raw datasets (default: $OUTPUT_DIR)"
    echo "  -l language      Language filter (default: $LANGUAGE)"
    echo "  -s min_stars     Minimum stars filter (default: $MIN_STARS)"
    echo "  -n max_results   Max repos to fetch (default: $MAX_RESULTS)"
    echo "  -t token         GitHub token (default: value in script)"
    echo "  -e exclude_repos  Comma-separated list of repos to exclude (format: org/repo)"
    echo "  -c created_at    Fetch PRs/Issues created on or after this date (default: $CREATED_AT)"
    echo "  -k key_words     Search keywords for PRs/Issues (default: $KEY_WORDS)"
    exit 1
}

# Parse command-line options
while getopts ":o:l:s:n:t:e:c:k:h" opt; do
  case $opt in
    o) OUTPUT_DIR="$OPTARG" ;;
    l) LANGUAGE="$OPTARG" ;;
    s) MIN_STARS="$OPTARG" ;;
    n) MAX_RESULTS="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    e) EXCLUDE_REPOS="$OPTARG" ;;
    c) CREATED_AT="$OPTARG" ;;
    k) KEY_WORDS="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
shift $((OPTIND -1))

# Default OUTPUT_DIR if not provided
if [ -z "$OUTPUT_DIR" ]; then
    # Replace spaces with underscores for the filesystem path
    KEY_WORDS_SAFE=$(echo "$KEY_WORDS" | tr ' ' '_')
    if [ "$KEY_WORDS_SAFE" = "" ]; then
        KEY_WORDS_SAFE="no_key_words"
    fi
    OUTPUT_DIR="data/raw_datasets/${TODAY}/${KEY_WORDS_SAFE}"
fi

# Display current configuration
echo "Configuration:"
echo "  OUTPUT_DIR = $OUTPUT_DIR"
echo "  LANGUAGE   = $LANGUAGE"
echo "  MIN_STARS  = $MIN_STARS"
echo "  MAX_RESULTS= $MAX_RESULTS"
echo "  EXCLUDE_REPOS = ${EXCLUDE_REPOS:-<none>}"

# If token not provided via -t, try reading from common environment variables
if [ "$TOKEN" = "xxxxx" ] || [ -z "$TOKEN" ]; then
    TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_API_TOKEN:-}}}"
    if [ -z "$TOKEN" ]; then
        echo "❌ Error: GitHub token not provided. Set with -t or export GITHUB_TOKEN/GH_TOKEN/GITHUB_API_TOKEN." >&2
        exit 1
    else
        echo "Using GitHub token from environment."
    fi
fi

# If TOKEN points to a file (e.g., ./tokens.txt), read non-empty lines and convert to CSV string
if [ -f "$TOKEN" ]; then
    echo "TOKEN is a file path, reading tokens from: $TOKEN"
    # Read non-empty lines, trim whitespace, then merge into a comma-separated string
    TOKENS_CSV=$(awk 'NF{gsub(/^[ \t]+|[ \t]+$/, ""); print}' "$TOKEN" | paste -sd, -)
    if [ -z "$TOKENS_CSV" ]; then
        echo "❌ Error: Token file $TOKEN is empty or contains only whitespace." >&2
        exit 1
    fi
    TOKEN="$TOKENS_CSV"
    # Optional: Display the number of tokens read (do not print specific tokens)
    TOKEN_COUNT=$(echo "$TOKEN" | awk -F',' '{print NF}')
    echo "Read $TOKEN_COUNT tokens from file."
fi

# Find suitable Python interpreter (requires Python >= 3.10)
PYTHON_CMD=""
for cmd in python python3 python3.11 python3.10; do
    if command -v $cmd >/dev/null 2>&1; then
        ver=$($cmd -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        maj=$(echo "$ver" | cut -d. -f1)
        min=$(echo "$ver" | cut -d. -f2)
        if [ "$maj" -gt 3 ] || { [ "$maj" -eq 3 ] && [ "$min" -ge 10 ]; }; then
            PYTHON_CMD=$cmd
            break
        fi
    fi
done
if [ -z "$PYTHON_CMD" ]; then
    echo "❌ Error: Python >= 3.10 is required. Activate your env (e.g., conda activate py311) or install Python 3.10+." >&2
    exit 1
fi

echo "Using interpreter: $PYTHON_CMD ($($PYTHON_CMD -V 2>&1))"

# Step 1: Crawl GitHub repositories
echo "Step 1: Crawl GitHub repos..."
$PYTHON_CMD -m multi_swe_bench.collect.crawl_repos \
    --output_dir "$OUTPUT_DIR" \
    --language "$LANGUAGE" \
    --min_stars "$MIN_STARS" \
    --max_results "$MAX_RESULTS" \
    --token "$TOKEN"

# Find the recently generated CSV file
CSV_FILE=$(ls -t "$OUTPUT_DIR"/github_${LANGUAGE}_repos_*.csv | head -n 1)
echo "Generated CSV file: $CSV_FILE"

echo "Step 1.1: Filter repos..."
$PYTHON_CMD -m multi_swe_bench.collect.filter_repo \
    --input_file "$CSV_FILE" \
    --output_file "$OUTPUT_DIR/filtered_repos_$LANGUAGE.csv" \
    --tokens_file "./tokens.txt" \
    --min_total_pr_issues 200 \
    --min_forks 200 \
    --language "$LANGUAGE" \
    --min_lang_percent "$PERCENTAGE" \
    --max_workers 10 \
    --exclude_repos "$EXCLUDE_REPOS"
# Update CSV_FILE to the filtered file
CSV_FILE="$OUTPUT_DIR/filtered_repos_$LANGUAGE.csv"
echo "Filtered CSV file: $CSV_FILE"

# Step 2: Get data from repositories
echo "Step 2: Get data from repos..."
$PYTHON_CMD -m multi_swe_bench.collect.get_from_repos_pipeline \
    --csv_file "$CSV_FILE" \
    --out_dir "$OUTPUT_DIR" \
    --max_workers "$MAX_WORKERS" \
    --distribute "$DISTRIBUTE" \
    --delay-on-error "$DELAY_ON_ERROR" \
    --retry-attempts "$RETRY_ATTEMPTS" \
    --key_words "$KEY_WORDS" \
    --created_at "$CREATED_AT" \
    --token "$TOKEN" \
    --exclude-repos "$EXCLUDE_REPOS"

echo "All done!"

# move to copy_raw_dataset.sh
# If *_raw_dataset.jsonl files exist and size > 0 in out_dir, copy to parent raw_datasets directory
# RAW_DATASET_FILES=("$OUTPUT_DIR"/*_raw_dataset.jsonl)
# for file in "${RAW_DATASET_FILES[@]}"; do
#     if [ -f "$file" ] && [ -s "$file" ]; then
#         cp "$file" "data/raw_datasets/"
#         echo "Copied $file to data/raw_datasets/"
#     fi
# done