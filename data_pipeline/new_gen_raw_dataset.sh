#!/bin/bash
set -e

LANGUAGE="Python"
MIN_STARS=100
MAX_RESULTS=1000
TOKEN="./tokens.txt"
OUTPUT_DIR=""
MERGED_AFTER=""
MERGED_BEFORE=""
KEYWORDS=""
QUERY=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Generate raw dataset by fetching GitHub repos and PRs sequentially."
    echo ""
    echo "Options:"
    echo "  -l LANGUAGE       Language to search (default: $LANGUAGE)"
    echo "  -s MIN_STARS      Minimum stars filter (default: $MIN_STARS)"
    echo "  -n MAX_RESULTS    Max repos to fetch (default: $MAX_RESULTS)"
    echo "  -t TOKEN          GitHub token or token file (default: $TOKEN)"
    echo "  -o OUTPUT_DIR     Output directory for results (required)"
    echo "  -m MERGED_AFTER   Fetch PRs merged after this date (ISO format, e.g., 2025-01-01)"
    echo "  -M MERGED_BEFORE  Fetch PRs merged before this date (ISO format, e.g., 2025-12-31)"
    echo "  -k KEYWORDS       Keywords to append to search query"
    echo "  -q QUERY          Custom search query (overrides -l, -s, -k)"
    echo "  -h                Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -l Go -s 1000 -n 500 -o ./output -m 2025-01-01"
    echo "  $0 -q 'language:typescript stars:>1000' -o ./output -m 2024-06-01"
    exit 1
}

while getopts ":l:s:n:t:o:m:M:k:q:h" opt; do
  case $opt in
    l) LANGUAGE="$OPTARG" ;;
    s) MIN_STARS="$OPTARG" ;;
    n) MAX_RESULTS="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    m) MERGED_AFTER="$OPTARG" ;;
    M) MERGED_BEFORE="$OPTARG" ;;
    k) KEYWORDS="$OPTARG" ;;
    q) QUERY="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
shift $((OPTIND -1))

if [ -z "$OUTPUT_DIR" ]; then
    echo "❌ Error: OUTPUT_DIR is required. Use -o to specify." >&2
    usage
fi

mkdir -p "$OUTPUT_DIR"

echo "Configuration:"
echo "  LANGUAGE     = $LANGUAGE"
echo "  MIN_STARS    = $MIN_STARS"
echo "  MAX_RESULTS  = $MAX_RESULTS"
echo "  OUTPUT_DIR   = $OUTPUT_DIR"
echo "  MERGED_AFTER = ${MERGED_AFTER:-<not set>}"
echo "  MERGED_BEFORE= ${MERGED_BEFORE:-<not set>}"
echo "  KEYWORDS     = ${KEYWORDS:-<not set>}"
echo "  TOKEN        = $TOKEN"

if [ -f "$TOKEN" ]; then
    echo "TOKEN is a file path, reading tokens from: $TOKEN"
else
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "xxxxx" ]; then
        TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_API_TOKEN:-}}}"
        if [ -z "$TOKEN" ]; then
            echo "❌ Error: GitHub token not provided. Set with -t or export GITHUB_TOKEN/GH_TOKEN/GITHUB_API_TOKEN." >&2
            exit 1
        else
            echo "Using GitHub token from environment."
        fi
    fi
fi

PYTHON_CMD=""
for cmd in python python3 python3.13 python3.12 python3.11 python3.10; do
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
    echo "❌ Error: Python >= 3.10 is required." >&2
    exit 1
fi

echo "Using interpreter: $PYTHON_CMD ($($PYTHON_CMD -V 2>&1))"

if [ -z "$QUERY" ]; then
    QUERY="language:$LANGUAGE stars:>$MIN_STARS"
    if [ -n "$KEYWORDS" ]; then
        QUERY="$QUERY $KEYWORDS"
    fi
fi

REPOS_CSV="$OUTPUT_DIR/repos.csv"
PRS_JSONL="$OUTPUT_DIR/prs.jsonl"

echo ""
echo "Step 1: Fetching GitHub repos with query: $QUERY"
$PYTHON_CMD -m multi_swe_bench.collect.fetch_github_repo_gql search \
    --query "$QUERY" \
    --max "$MAX_RESULTS" \
    --tokens "$TOKEN" \
    --output "$REPOS_CSV"

if [ ! -f "$REPOS_CSV" ] || [ ! -s "$REPOS_CSV" ]; then
    echo "❌ Error: Failed to generate repos CSV file or file is empty." >&2
    exit 1
fi

echo "✅ Generated repos CSV: $REPOS_CSV"
REPO_COUNT=$(tail -n +2 "$REPOS_CSV" | wc -l)
echo "   Found $REPO_COUNT repositories"

echo ""
echo "Step 2: Fetching PRs from repositories"
TOKEN_ARGS=""
if [ -n "$TOKEN" ]; then
    TOKEN_ARGS="--tokens $TOKEN"
fi

MERGED_ARGS=""
if [ -n "$MERGED_AFTER" ]; then
    MERGED_ARGS="$MERGED_ARGS --merged-after $MERGED_AFTER"
fi
if [ -n "$MERGED_BEFORE" ]; then
    MERGED_ARGS="$MERGED_ARGS --merged-before $MERGED_BEFORE"
fi

$PYTHON_CMD /Users/jasonzhou/work/python/onttech/multi-swe-bench/multi_swe_bench/collect/new_fetch_prs.py \
    --input "$REPOS_CSV" \
    --output "$PRS_JSONL" \
    $MERGED_ARGS \
    $TOKEN_ARGS

if [ ! -f "$PRS_JSONL" ] || [ ! -s "$PRS_JSONL" ]; then
    echo "❌ Error: Failed to generate PRs JSONL file or file is empty." >&2
    exit 1
fi

echo "✅ Generated PRs JSONL: $PRS_JSONL"
PR_COUNT=$(wc -l < "$PRS_JSONL")
echo "   Found $PR_COUNT PRs"

echo ""
echo "🎉 All done! Output files:"
echo "   - Repos: $REPOS_CSV"
echo "   - PRs:   $PRS_JSONL"
