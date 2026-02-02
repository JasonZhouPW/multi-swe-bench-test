#!/usr/bin/env bash
# analyze_semgrep_patch.sh - Analyze patches with semgrep in cloned repos
# Usage: ./analyze_semgrep_patch.sh <diffs_directory> <output_directory>

set -euo pipefail

DIFFS_DIR="${1:?Usage: $0 <diffs_directory> <output_directory>}"
OUTPUT_DIR="${2:?Usage: $0 <diffs_directory> <output_directory>}"

mkdir -p "$OUTPUT_DIR"
REPOS_DIR="$OUTPUT_DIR/repos"
mkdir -p "$REPOS_DIR"

CSV_OUTPUT="$OUTPUT_DIR/patch_analysis_results.csv"
echo "org,repo,pr_number,patch_file,semgrep_score,comments" > "$CSV_OUTPUT"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for this script." >&2
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo "Error: bc is required for this script." >&2
    exit 1
fi

echo "Analyzing patches in: $DIFFS_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Repos directory: $REPOS_DIR"
echo ""

TOTAL_PATCHES=$(ls "$DIFFS_DIR"/*.diff 2>/dev/null | wc -l)
PROCESSED_PATCHES=0
echo "Total patches to process: $TOTAL_PATCHES"
echo ""

for diff_file in "$DIFFS_DIR"/*.diff; do
    if [ ! -f "$diff_file" ]; then
        echo "No diff files found in $DIFFS_DIR"
        exit 0
    fi

    filename=$(basename "$diff_file" .diff)
    IFS='_' read -r ORG REPO PR_NUMBER BASE_COMMIT <<< "$filename"

    REPO_PATH="$REPOS_DIR/$ORG/$REPO"

    if [ ! -d "$REPO_PATH" ]; then
        echo "[$((PROCESSED_PATCHES + 1))/$TOTAL_PATCHES] Cloning $ORG/$REPO ..."
        mkdir -p "$REPOS_DIR/$ORG"
        git clone --quiet "https://github.com/$ORG/$REPO.git" "$REPO_PATH" || {
            echo "Warning: Failed to clone $ORG/$REPO, skipping..."
            continue
        }
    fi

    if [ "$BASE_COMMIT" != "unknown" ] && [ -n "$BASE_COMMIT" ]; then
        echo "[$((PROCESSED_PATCHES + 1))/$TOTAL_PATCHES] Checking out $BASE_COMMIT for $ORG/$REPO..."
        (cd "$REPO_PATH" && git checkout --quiet "$BASE_COMMIT" 2>/dev/null || true)
    fi

    echo "[$((PROCESSED_PATCHES + 1))/$TOTAL_PATCHES] Analyzing $ORG/$REPO #$PR_NUMBER..."

    cp "$diff_file" "$REPO_PATH/"
    cp ./scripts/semgrep_scan.sh "$REPO_PATH/"
    cp ./scripts/analyze_patch.sh "$REPO_PATH/"

    SEMGREP_OUTPUT="$OUTPUT_DIR/semgrep_${ORG}_${REPO}_${PR_NUMBER}.json"

    (cd "$REPO_PATH" && bash semgrep_scan.sh "$(basename "$diff_file")" "$SEMGREP_OUTPUT") 2>&1 >/dev/null || {
        echo "  Warning: Semgrep scan failed for $(basename "$diff_file")"
        continue
    }

    SCORE_OUTPUT=$(cd "$REPO_PATH" && bash analyze_patch.sh "$SEMGREP_OUTPUT" 2>&1)

    SCORE=$(echo "$SCORE_OUTPUT" | grep "^SCORE:" | cut -d':' -f2-)
    COMMENTS=$(echo "$SCORE_OUTPUT" | grep "^COMMENTS:" | cut -d':' -f2- | sed 's/,/;/g')

    if [ -z "$SCORE" ]; then
        SCORE="100.0"
    fi

    if [ -z "$COMMENTS" ]; then
        COMMENTS=""
    fi

    echo "$ORG,$REPO,$PR_NUMBER,$diff_file,$SCORE,\"$COMMENTS\"" >> "$CSV_OUTPUT"

    rm -f "$REPO_PATH/$(basename "$diff_file")"
    rm -f "$REPO_PATH/semgrep_scan.sh"
    rm -f "$REPO_PATH/analyze_patch.sh"

    ((PROCESSED_PATCHES++))
    echo "  Done. Score: $SCORE"

    if [ $((PROCESSED_PATCHES % 10)) -eq 0 ]; then
        echo "  Progress: $PROCESSED_PATCHES patches processed"
    fi
done

echo ""
echo "Analysis completed!"
echo "Total patches processed: $PROCESSED_PATCHES"
echo "Results saved to: $CSV_OUTPUT"
