#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the project root
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure multi_swe_bench is in PYTHONPATH
export PYTHONPATH="$PROJ_ROOT${PYTHONPATH:+:$PYTHONPATH}"

##########################################
# Check input arguments
##########################################
if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw_dataset_file.jsonl>"
    echo "Example: $0 mark3labs__mcp-go_raw_dataset.jsonl"
    echo "         $0 data/raw_datasets/mark3labs__mcp-go_raw_dataset.jsonl"
    exit 1
fi

##########################################
# Automatically handle paths and filenames
##########################################
RAW_PATH="$1"

    # If a relative path is passed, keep it; if only a filename, use default path
    if [ ! -f "$RAW_PATH" ]; then
        # Try finding it in the default directory
        if [ -f "./data/raw_datasets/$RAW_PATH" ]; then
            RAW_PATH="./data/raw_datasets/$RAW_PATH"
    else
        echo "❌ Error: Cannot find file: $RAW_PATH"
        exit 1
    fi
fi

# Parse filename and directory
RAW_FILE="$(basename "$RAW_PATH")"
RAW_DIR="$(dirname "$RAW_PATH")"

##########################################
# Automatically derive variables
##########################################
BASE_NAME="${RAW_FILE%%_raw_dataset.jsonl}"

WORKDIR="$PROJ_ROOT/data/workdir"
OUTPUT_DIR="$PROJ_ROOT/data/datasets"
LOG_DIR="$PROJ_ROOT/data/logs"
REPO_DIR="$PROJ_ROOT/data/repos"
TEMP_DIR="$PROJ_ROOT/data/temp_dataset"

mkdir -p "$WORKDIR" "$OUTPUT_DIR" "$LOG_DIR" "$REPO_DIR" "$TEMP_DIR"

FINAL_OUTPUT="${OUTPUT_DIR}/${BASE_NAME}_dataset.jsonl"
: > "$FINAL_OUTPUT"

# Initialize processing log
PROCESSING_LOG="${LOG_DIR}/${BASE_NAME}_processing.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "========================================" > "$PROCESSING_LOG"
echo "Processing Log: $BASE_NAME" >> "$PROCESSING_LOG"
echo "Started: $TIMESTAMP" >> "$PROCESSING_LOG"
echo "========================================" >> "$PROCESSING_LOG"
echo "" >> "$PROCESSING_LOG"

# Counters for summary
TOTAL_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0

echo "🚀 Multi-record dataset builder"
echo "📌 Input file: $RAW_PATH"
echo "📝 Processing log: $PROCESSING_LOG"
echo ""

##########################################
# Get line count
##########################################
LINE_COUNT=$(wc -l < "$RAW_PATH" | tr -d ' ')
echo "📌 Total records: $LINE_COUNT"
echo ""

if [ "$LINE_COUNT" -eq 0 ]; then
    echo "❌ No data in file."
    exit 1
fi

##########################################
# Iterate through each JSONL line
##########################################
index=0
while IFS= read -r LINE; do
    echo "============================================"
    echo "📄 Processing record #$index"
    echo "============================================"

    TEMP_RAW_FILE="$TEMP_DIR/${BASE_NAME}_single_${index}.jsonl"
    CONFIG_FILE="$TEMP_DIR/config_${BASE_NAME}_${index}.json"
    SINGLE_OUT="${OUTPUT_DIR}/${BASE_NAME}_${index}_dataset.jsonl"

    # Extract PR info for logging
    PR_ORG=$(echo "$LINE" | jq -r '.org // "unknown"')
    PR_REPO=$(echo "$LINE" | jq -r '.repo // "unknown"')
    PR_NUMBER=$(echo "$LINE" | jq -r '.number // "unknown"')
    PR_ID="${PR_ORG}/${PR_REPO}#${PR_NUMBER}"

    RECORD_START=$(date '+%Y-%m-%d %H:%M:%S')
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    ##########################################
    # Clean JSON: use jq -c to ensure valid single-line JSON
    ##########################################
    echo "$LINE" | jq -c '.' > "$TEMP_RAW_FILE"

    ##########################################
    # Generate config file
    ##########################################
    cat > "$CONFIG_FILE" << EOF
{
    "mode": "dataset",
    "workdir": "$WORKDIR",
    "raw_dataset_files": [
        "$TEMP_RAW_FILE"
    ],
    "force_build": false,
    "output_dir": "$OUTPUT_DIR",
    "specifics": [],
    "skips": [],
    "repo_dir": "$REPO_DIR",
    "need_clone": false,
    "global_env": [],
    "clear_env": true,
    "stop_on_error": false,
    "max_workers": 2,
    "max_workers_build_image": 8,
    "max_workers_run_instance": 8,
    "log_dir": "$LOG_DIR",
    "log_level": "DEBUG"
}
EOF

    ##########################################
    # Execute single build
    ##########################################
    echo "🚀 Running dataset builder for record #$index..."
    echo "   PR: $PR_ID"

    # Capture output and exit code
    BUILD_OUTPUT=$(python -m multi_swe_bench.harness.build_dataset --config "$CONFIG_FILE" 2>&1)
    BUILD_EXIT_CODE=$?

    RECORD_END=$(date '+%Y-%m-%d %H:%M:%S')

    if [ -f "$SINGLE_OUT" ]; then
        echo "✅ Success: record #$index ($PR_ID)"
        cat "$SINGLE_OUT" >> "$FINAL_OUTPUT"
        rm -f "$SINGLE_OUT"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

        # Log success
        echo "[$RECORD_END] ✅ SUCCESS | $PR_ID | Record #$index" >> "$PROCESSING_LOG"
    else
        echo "❌ Failed: record #$index ($PR_ID)"
        FAIL_COUNT=$((FAIL_COUNT + 1))

        # Extract detailed error reasons from build output
        ERROR_COMMIT=$(echo "$BUILD_OUTPUT" | grep -E "Commit hash not found" | head -1 || true)
        ERROR_IMAGE=$(echo "$BUILD_OUTPUT" | grep -E "Error building image" | head -1 || true)
        ERROR_DOCKER=$(echo "$BUILD_OUTPUT" | grep -E "Docker build failed" | head -1 || true)
        ERROR_RUN=$(echo "$BUILD_OUTPUT" | grep -E "Error running instance" | head -1 || true)
        ERROR_COPY=$(echo "$BUILD_OUTPUT" | grep -E "No such file or directory" | head -1 || true)
        ERROR_GENERAL=$(echo "$BUILD_OUTPUT" | grep -E "^\[ERROR\]" | head -1 || true)

        # Determine primary error reason
        ERROR_REASON=""
        if [ -n "$ERROR_COMMIT" ]; then
            ERROR_REASON="Commit hash not found: $(echo "$ERROR_COMMIT" | sed 's/.*Commit hash not found.*/Commit hash not found/')"
            echo "   ⚠️  Reason: Commit hash not found in repository"
        elif [ -n "$ERROR_IMAGE" ]; then
            ERROR_REASON="Image build failed: $(echo "$ERROR_IMAGE" | sed 's/.*Error building image //' | cut -c1-80)"
            echo "   ⚠️  Reason: Docker image build failed"
        elif [ -n "$ERROR_DOCKER" ]; then
            ERROR_REASON="Docker build failed: $(echo "$ERROR_DOCKER" | sed 's/.*returned a non-zero code.*/Docker build error/' | cut -c1-80)"
            echo "   ⚠️  Reason: Docker build returned non-zero code"
        elif [ -n "$ERROR_RUN" ]; then
            ERROR_REASON="Instance run failed: $(echo "$ERROR_RUN" | sed 's/.*Error running instance //' | cut -c1-80)"
            echo "   ⚠️  Reason: Instance execution failed"
        elif [ -n "$ERROR_COPY" ]; then
            ERROR_REASON="File not found: $(echo "$ERROR_COPY" | sed 's/.*No such file or directory.*/Missing file/' | cut -c1-80)"
            echo "   ⚠️  Reason: Missing file during copy"
        elif [ -n "$ERROR_GENERAL" ]; then
            ERROR_REASON="$ERROR_GENERAL"
            echo "   ⚠️  Reason: $ERROR_GENERAL"
        else
            ERROR_REASON="Unknown error (no output file generated)"
            echo "   ⚠️  Reason: Unknown - no dataset file generated"
        fi

        # Log failure with detailed reason
        echo "[$RECORD_END] ❌ FAILED | $PR_ID | Record #$index | $ERROR_REASON" >> "$PROCESSING_LOG"
    fi

    # Show progress
    echo ""
    echo "📊 Progress: $((index + 1))/$LINE_COUNT | ✅ $SUCCESS_COUNT | ❌ $FAIL_COUNT"

    index=$((index + 1))
    echo ""
done < "$RAW_PATH"

rm -rf "$TEMP_DIR"

##########################################
# Summary output
##########################################
END_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Calculate success rate
if [ "$TOTAL_COUNT" -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=1; $SUCCESS_COUNT * 100 / $TOTAL_COUNT" | bc)
else
    SUCCESS_RATE="0.0"
fi

echo "" >> "$PROCESSING_LOG"
echo "========================================" >> "$PROCESSING_LOG"
echo "Summary" >> "$PROCESSING_LOG"
echo "========================================" >> "$PROCESSING_LOG"
echo "Finished: $END_TIMESTAMP" >> "$PROCESSING_LOG"
echo "Total records: $TOTAL_COUNT" >> "$PROCESSING_LOG"
echo "Successful: $SUCCESS_COUNT" >> "$PROCESSING_LOG"
echo "Failed: $FAIL_COUNT" >> "$PROCESSING_LOG"
echo "Success rate: ${SUCCESS_RATE}%" >> "$PROCESSING_LOG"

echo "======================================="
echo "🎉 Multi-record dataset build completed"
echo "📦 Output file: $FINAL_OUTPUT"
echo "📝 Processing log: $PROCESSING_LOG"
echo "📊 Summary: $SUCCESS_COUNT/$TOTAL_COUNT records succeeded (${SUCCESS_RATE}%)"
echo "======================================="