#!/bin/bash

# Verify AI-generated fix-patch effectiveness
# This script wraps verify_ai_fix_patch.py for easy command-line usage

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default output directory
OUTPUT_DIR="${BASE_DIR}/verify_output/$(date +%Y%m%d_%H%M%S)"

usage() {
    cat << EOF
Usage: $0 --dataset-json <path> [OPTIONS]

Verify AI-generated fix-patch effectiveness.

Required:
  --dataset-json <path>    Path to the dataset JSON file (e.g., *_dataset.json)

Optional:
  --output-dir <path>      Output directory for logs and reports
                           Default: ./verify_output/YYYYMMDD_HHMMSS
  --image-name <name>      Docker image name (auto-generated if not provided)
  --instance-dir <path>    Instance directory with run.sh, test-run.sh, fix-run.sh
                           Auto-detected from dataset-json location if not provided
  --fix-patch <file>       Path to fix-patch file (overrides dataset JSON)
  --test-patch <file>      Path to test-patch file (overrides dataset JSON)
  --help                   Show this help message

Examples:
  # Verify using fix_patch from dataset JSON
  $0 --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json

  # Verify with external fix-patch file (e.g., AI-generated patch)
  $0 --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \\
     --fix-patch /path/to/ai-generated-fix.patch

  # Verify with both external patch files
  $0 --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \\
     --fix-patch /path/to/fix.patch \\
     --test-patch /path/to/test.patch
EOF
}

# Parse arguments
DATASET_JSON=""
IMAGE_NAME=""
INSTANCE_DIR=""
FIX_PATCH=""
TEST_PATCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dataset-json)
            DATASET_JSON="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --instance-dir)
            INSTANCE_DIR="$2"
            shift 2
            ;;
        --fix-patch)
            FIX_PATCH="$2"
            shift 2
            ;;
        --test-patch)
            TEST_PATCH="$2"
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
if [ -z "$DATASET_JSON" ]; then
    echo "❌ Error: --dataset-json is required"
    usage
    exit 1
fi

# Check if dataset JSON exists
if [ ! -f "$DATASET_JSON" ]; then
    echo "❌ Error: Dataset JSON not found: $DATASET_JSON"
    exit 1
fi

# Try to auto-detect instance directory if not provided
if [ -z "$INSTANCE_DIR" ]; then
    DATASET_DIR="$(dirname "$DATASET_JSON")"
    if [ -d "$DATASET_DIR/image" ] && [ -f "$DATASET_DIR/image/run.sh" ]; then
        INSTANCE_DIR="$DATASET_DIR/image"
        echo "🔍 Auto-detected instance directory: $INSTANCE_DIR"
    elif [ -f "$DATASET_DIR/run.sh" ]; then
        INSTANCE_DIR="$DATASET_DIR"
        echo "🔍 Auto-detected instance directory: $INSTANCE_DIR"
    fi
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo "📁 Output directory: $OUTPUT_DIR"

# Build command
CMD="python3 $SCRIPT_DIR/verify_ai_fix_patch.py"
CMD="$CMD --dataset-json $DATASET_JSON"
CMD="$CMD --output-dir $OUTPUT_DIR"

if [ -n "$IMAGE_NAME" ]; then
    CMD="$CMD --image-name $IMAGE_NAME"
fi

if [ -n "$INSTANCE_DIR" ]; then
    CMD="$CMD --instance-dir $INSTANCE_DIR"
fi

if [ -n "$FIX_PATCH" ]; then
    CMD="$CMD --fix-patch $FIX_PATCH"
fi

if [ -n "$TEST_PATCH" ]; then
    CMD="$CMD --test-patch $TEST_PATCH"
fi

# Run verification
echo ""
echo "========================================="
echo "🚀 Running verification..."
echo "========================================="
$CMD

echo ""
echo "========================================="
echo "✅ Verification script completed"
echo "========================================="
echo "Output directory: $OUTPUT_DIR"
echo "Report file: $OUTPUT_DIR/report.json"
echo ""
