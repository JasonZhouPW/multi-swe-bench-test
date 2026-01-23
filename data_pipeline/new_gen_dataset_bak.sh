#!/bin/bash
set -e

PYTHON_CMD="${PYTHON_CMD:-python}"
TODAY=$(date +%Y-%m-%d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LANGUAGE="Go"
MIN_STARS=100
MAX_RESULTS=500
MERGED_AFTER="2024-01-01"
MERGED_BEFORE="2025-12-31"
TOKEN="./data_pip//eline/tokens.txt"
OUTPUT_DIR=""

usage() {
    echo "Usage: $0 [-o output_dir] [-l language] [-s min_stars] [-n max_results] [-t token] [-a merged_after] [-b merged_before]"
    echo "  -o output_dir      Output directory for raw datasets"
    echo "  -l language        Language filter (default: Go)"
    echo "  -s minima_stars       Minimum stars filter (default: 100)"
    echo "  -n max_results     Max repos to fetch (default: 500)"
    echo "  -t token           GitHub token or token file path"
    echo "  -a merged_after     Start date for merged PRs (default: 2024-01-01)"
    echo "  -b merged_before    End date for merged PRs (default: 2025-12-31)"
    echo "  -h                 Show this help message"
    exit 1
}

while getopts "o:l:s:n:t:a:b:h" opt; do
  case $opt in
    o) OUTPUT_DIR="$OPTARG" ;;
    l) LANGUAGE="$OPTARG" ;;
    s) MIN_STARS="$OPTARG" ;;
    n) MAX_RESULTS="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    a) MERGED_AFTER="$OPTARG" ;;
    b) MERGED_BEFORE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND -1))

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$SCRIPT_DIR/data/raw_datasets/$TODAY/new_pipeline"
fi

echo "Configuration:"
echo "  OUTPUT_DIR      = $OUTPUT_DIR"
echo "  LANGUAGE        = $LANGUAGE"
echo "  MIN_STARS       = $MIN_STARS"
echo "  MAX_RESULTS     = $MAX_RESULTS"
echo "  MERGED_AFTER    = $MERGED_AFTER"
echo "  MERGED_BEFORE   = $MERGED_BEFORE"
echo ""

if [ "$TOKEN" = "xxxxx" ] || [ -z "$TOKEN" ]; then
    TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_API_TOKEN:-}}"
    if [ -z "$TOKEN" ]; then
        echo "Error: GitHub token not provided." >&2
        exit 1
    else
        echo "Using GitHub token from environment."
    fi
fi

if [ -f "$TOKEN" ]; then
    echo "TOKEN is a file path, reading tokens from: $TOKEN"
    TOKENS_CSV=$(awk 'NF{gsub(/^[ \t]+|[ \t]+$/, ""); print}' "$TOKEN" | paste -sd, -)
    if [ -z "$TOKENS_CSV" ]; then
        echo "Warning: Token file $TOKEN is empty." >&2
        TOKEN=""
    else
        TOKEN="$TOKENS_CSV"
        TOKEN_COUNT=$(echo "$TOKEN" | awk -F',' '{print NF}')
        echo "Read $TOKEN_COUNT tokens from file"
    fi
fi

mkdir -p "$OUTPUT_DIR"

echo "Step 1: Search repositories"
QUERY="language:$LANGUAGE stars:>=$MIN_STARS"
echo "Search query: $QUERY"
echo "Max results: $MAX_RESULTS"

REPOS_CSV="$OUTPUT_DIR/repos_${LANGUAGE}.csv"

echo "Searching repositories using GraphQL API..."

$PYTHON_CMD -m multi_swe_bench.collect.fetch_github_repo_gql search \
    --query "$QUERY" \
    --max $MAX_RESULTS \
    --output "$REPOS_CSV" \
    --tokens "$TOKEN"

if [ ! -f "$REPOS_CSV" ]; then
    echo "Error: Failed to generate repository list"
    exit 1
fi

REPO_COUNT=$(tail -n +2 "$REPOS_CSV" | wc -l | tr -d ' ')
echo "Found $REPO_COUNT repositories"

echo "Step 2: Fetch merged PRs"
echo "Date range: $MERGED_AFTER to $MERGED_BEFORE"

PR_OUTPUT="$OUTPUT_DIR/filtered_prs_${LANGUAGE}.jsonl"

echo "Fetching merged PRs using GraphQL API..."

$PYTHON_CMD -m multi_swe_bench.collect.new_fetch_prs \
    --input "$REPOS_CSV" \
    --output "$PR_OUTPUT" \
    --merged-after "$MERGED_AFTER" \
    --merged-before "$MERGED_BEFORE" \
    --tokens "$TOKEN"

if [ ! -f "$PR_OUTPUT" ]; then
    echo "Error: Failed to generate PR list"
    exit 1
fi

PR_COUNT=$(wc -l < "$PR_OUTPUT" | tr -d ' ')
echo "Found $PR_COUNT merged PRs"

echo "Summary"
echo "Output directory: $OUTPUT_DIR"
echo "Repositories: $REPOS_CSV ($REPO_COUNT repos)"
echo "PRs: $PR_OUTPUT ($PR_COUNT PRs)"
echo ""
echo "Dataset generation completed successfully!"
