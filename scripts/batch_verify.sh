#!/bin/bash

# Batch verify AI-generated fix-patches
# This script verifies multiple fix-patches in a directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default output directory
OUTPUT_DIR="${BASE_DIR}/verify_output/$(date +%Y%m%d_%H%M%S)"

usage() {
    cat << EOF
Usage: $0 --dataset-dir <dir> --patch-dir <dir> [OPTIONS]

Batch verify multiple AI-generated fix-patches.

Required:
  --dataset-dir <dir>    Directory containing dataset JSON files (*_dataset.json)
  --patch-dir <dir>      Directory containing AI-generated fix-patch files
                         File naming: <org>_<repo>-<pr_number>.patch or .diff

Optional:
  --output-dir <path>    Output directory for logs and reports
                         Default: ./verify_output/YYYYMMDD_HHMMSS
  --test-patch-dir <dir> Directory containing test-patch files (optional)
                         File naming: <org>_<repo>-<pr_number>.patch or .diff
  --pattern <pattern>    File pattern to match (default: *.patch)
  --dry-run              Show what would be processed without running
  --parallel <N>         Number of parallel jobs (default: 1, sequential)
  --help                 Show this help message

File Naming Convention:
  Patches should be named to match dataset JSON files:
  - Dataset: OpenHands_OpenHands-13368_dataset.json
  - Patch:   OpenHands_OpenHands-13368.patch (or .diff)

Examples:
  # Batch verify all patches (sequential)
  $0 --dataset-dir datasets/ --patch-dir ai_patches/

  # Batch verify with custom output directory
  $0 --dataset-dir datasets/ --patch-dir ai_patches/ \\
     --output-dir ./batch_verify_output

  # Dry run to see what will be processed
  $0 --dataset-dir datasets/ --patch-dir ai_patches/ --dry-run

  # Run with 4 parallel jobs
  $0 --dataset-dir datasets/ --patch-dir ai_patches/ --parallel 4
EOF
}

# Parse arguments
DATASET_DIR=""
PATCH_DIR=""
TEST_PATCH_DIR=""
PATTERN="*.patch"
DRY_RUN=false
PARALLEL=1

while [[ $# -gt 0 ]]; do
    case $1 in
        --dataset-dir)
            DATASET_DIR="$2"
            shift 2
            ;;
        --patch-dir)
            PATCH_DIR="$2"
            shift 2
            ;;
        --test-patch-dir)
            TEST_PATCH_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --pattern)
            PATTERN="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check required arguments
if [ -z "$DATASET_DIR" ] || [ -z "$PATCH_DIR" ]; then
    echo "❌ Error: --dataset-dir and --patch-dir are required"
    usage
    exit 1
fi

# Check directories exist
if [ ! -d "$DATASET_DIR" ]; then
    echo "❌ Error: Dataset directory not found: $DATASET_DIR"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "❌ Error: Patch directory not found: $PATCH_DIR"
    exit 1
fi

if [ -n "$TEST_PATCH_DIR" ] && [ ! -d "$TEST_PATCH_DIR" ]; then
    echo "❌ Error: Test patch directory not found: $TEST_PATCH_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo "📁 Output directory: $OUTPUT_DIR"

# Find all patch files and match with dataset JSON files
echo ""
echo "🔍 Scanning for patch files..."

# Arrays to store matched pairs
declare -a DATASET_FILES=()
declare -a PATCH_FILES=()
declare -a TEST_PATCH_FILES=()

# Find all patch files
for patch_file in "$PATCH_DIR"/$PATTERN; do
    [ -f "$patch_file" ] || continue

    # Extract base name (without .patch or .diff extension)
    patch_basename=$(basename "$patch_file")
    patch_base="${patch_basename%.patch}"
    patch_base="${patch_base%.diff}"

    # Look for matching dataset JSON
    dataset_file="$DATASET_DIR/${patch_base}_dataset.json"

    if [ -f "$dataset_file" ]; then
        DATASET_FILES+=("$dataset_file")
        PATCH_FILES+=("$patch_file")

        # Look for matching test patch if test patch dir is provided
        test_patch_file=""
        if [ -n "$TEST_PATCH_DIR" ]; then
            for ext in .patch .diff; do
                if [ -f "$TEST_PATCH_DIR/${patch_base}${ext}" ]; then
                    test_patch_file="$TEST_PATCH_DIR/${patch_base}${ext}"
                    break
                fi
            done
        fi
        TEST_PATCH_FILES+=("$test_patch_file")
    else
        echo "⚠️  No matching dataset JSON for: $patch_basename"
    fi
done

# Report findings
total_found=${#DATASET_FILES[@]}
echo "Found $total_found patch-dataset pair(s)"

if [ $total_found -eq 0 ]; then
    echo "❌ No matching files found. Check your file naming."
    exit 1
fi

# Print what will be processed
echo ""
echo "Files to process:"
for i in "${!DATASET_FILES[@]}"; do
    dataset_basename=$(basename "${DATASET_FILES[$i]}")
    patch_basename=$(basename "${PATCH_FILES[$i]}")
    test_patch="${TEST_PATCH_FILES[$i]}"
    if [ -n "$test_patch" ]; then
        echo "  $((i+1)). $dataset_basename + $patch_basename + $(basename $test_patch)"
    else
        echo "  $((i+1)). $dataset_basename + $patch_basename"
    fi
done

# Dry run - just show what would be processed
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "🔍 Dry run - no verification performed"
    exit 0
fi

# Summary file
SUMMARY_FILE="$OUTPUT_DIR/batch_summary.txt"
echo "Batch Verification Summary" > "$SUMMARY_FILE"
echo "==========================" >> "$SUMMARY_FILE"
echo "Date: $(date)" >> "$SUMMARY_FILE"
echo "Dataset Dir: $DATASET_DIR" >> "$SUMMARY_FILE"
echo "Patch Dir: $PATCH_DIR" >> "$SUMMARY_FILE"
echo "Output Dir: $OUTPUT_DIR" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Counters
success_count=0
fail_count=0
error_count=0

# Process each pair
echo ""
echo "========================================="
echo "🚀 Starting batch verification..."
echo "========================================="
echo ""

process_pair() {
    local dataset_file="$1"
    local patch_file="$2"
    local test_patch_file="$3"
    local index="$4"
    local total="$5"

    dataset_basename=$(basename "$dataset_file")
    patch_basename=$(basename "$patch_file")

    # Extract org_repo-pr from patch file name
    patch_base="${patch_basename%.patch}"
    patch_base="${patch_base%.diff}"

    # Create output subdirectory for this patch
    local pair_output_dir="$OUTPUT_DIR/$patch_base"
    mkdir -p "$pair_output_dir"

    echo "[$index/$total] Processing: $patch_base"
    echo "  Dataset: $dataset_basename"
    echo "  Patch:   $patch_basename"

    # Build command
    local cmd="python3 $SCRIPT_DIR/verify_ai_fix_patch.py"
    cmd="$cmd --dataset-json $dataset_file"
    cmd="$cmd --fix-patch $patch_file"
    cmd="$cmd --output-dir $pair_output_dir"

    if [ -n "$test_patch_file" ]; then
        cmd="$cmd --test-patch $test_patch_file"
        echo "  Test:    $(basename $test_patch_file)"
    fi

    # Run verification
    echo "  Running verification..."
    if $cmd > "$pair_output_dir/verify.log" 2>&1; then
        echo "  ✅ VALID (fix passed >= original)"
        echo "[$index] $patch_base - VALID" >> "$SUMMARY_FILE"
        return 0
    else
        # Check exit code: 1 = invalid, other = error
        exit_code=$?
        if [ $exit_code -eq 1 ]; then
            echo "  ❌ INVALID (fix passed < original)"
            echo "[$index] $patch_base - INVALID" >> "$SUMMARY_FILE"
        else
            echo "  ⚠️  ERROR (execution failed)"
            echo "[$index] $patch_base - ERROR" >> "$SUMMARY_FILE"
        fi
        return 1
    fi
}

# Sequential processing
if [ "$PARALLEL" -le 1 ]; then
    for i in "${!DATASET_FILES[@]}"; do
        index=$((i+1))
        if process_pair "${DATASET_FILES[$i]}" "${PATCH_FILES[$i]}" "${TEST_PATCH_FILES[$i]}" "$index" "$total_found"; then
            ((success_count++))
        else
            # Check exit code to differentiate fail vs error
            pair_output_dir="$OUTPUT_DIR/$(basename "${PATCH_FILES[$i]}" .patch)"
            if [ -f "$pair_output_dir/verify.log" ]; then
                ((fail_count++))
            else
                ((error_count++))
            fi
        fi
        echo ""
    done
else
    # Parallel processing
    echo "Running with $PARALLEL parallel jobs..."
    echo ""

    # Create job list
    job_list=""
    for i in "${!DATASET_FILES[@]}"; do
        job_list="$job_list${DATASET_FILES[$i]}|${PATCH_FILES[$i]}|${TEST_PATCH_FILES[$i]}|$((i+1))|$total_found\n"
    done

    # Process in parallel
    echo "$job_list" | xargs -P "$PARALLEL" -I {} bash -c '
        IFS="|" read -r dataset patch test_patch index total <<< "{}"
        patch_base=$(basename "$patch" .patch)
        patch_base=${patch_base%.diff}
        pair_output_dir="'"$OUTPUT_DIR"'/$patch_base"
        mkdir -p "$pair_output_dir"

        cmd="python3 '"$SCRIPT_DIR"'/verify_ai_fix_patch.py --dataset-json \"$dataset\" --fix-patch \"$patch\" --output-dir \"$pair_output_dir\""
        if [ -n "$test_patch" ]; then
            cmd="$cmd --test-patch \"$test_patch\""
        fi

        echo "[$index/$total] Processing: $patch_base"
        if $cmd > "$pair_output_dir/verify.log" 2>&1; then
            echo "  ✅ VALID"
            echo "[$index] $patch_base - VALID" >> "'"$SUMMARY_FILE"'"
        else
            echo "  ❌ INVALID/ERROR"
            echo "[$index] $patch_base - INVALID" >> "'"$SUMMARY_FILE"'"
        fi
    '

    # Count results from summary file
    success_count=$(grep -c "VALID" "$SUMMARY_FILE" 2>/dev/null || echo 0)
    fail_count=$(grep -c "INVALID" "$SUMMARY_FILE" 2>/dev/null || echo 0)
    error_count=$(grep -c "ERROR" "$SUMMARY_FILE" 2>/dev/null || echo 0)
fi

# Print summary
echo ""
echo "========================================="
echo "📊 BATCH VERIFICATION SUMMARY"
echo "========================================="
echo "Total processed: $total_found"
echo "✅ Valid:   $success_count (fix >= original)"
echo "❌ Invalid: $fail_count (fix < original)"
echo "⚠️  Errors:  $error_count"
echo ""
echo "Summary file: $SUMMARY_FILE"
echo "Output directory: $OUTPUT_DIR"
echo "========================================="

# Generate JSON summary
JSON_SUMMARY="$OUTPUT_DIR/batch_summary.json"
cat > "$JSON_SUMMARY" << EOF
{
  "total": $total_found,
  "passed": $success_count,
  "failed": $fail_count,
  "errors": $error_count,
  "date": "$(date -Iseconds)",
  "dataset_dir": "$DATASET_DIR",
  "patch_dir": "$PATCH_DIR",
  "output_dir": "$OUTPUT_DIR"
}
EOF

echo "JSON summary: $JSON_SUMMARY"

# Exit with error if any failures
if [ $fail_count -gt 0 ] || [ $error_count -gt 0 ]; then
    exit 1
fi

exit 0
