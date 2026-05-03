#!/bin/bash
# ================================================================
# Merge Training Data Subdirectories
# ================================================================
#
# Usage: ./merge_training_data.sh [--cleanup]
#
# Merges jsonl files from subdirectories (e.g., OpenHands__OpenHands/)
# into root-level files (train_sft.jsonl, train_completion.jsonl, train_dpo.jsonl)
#
# Options:
#   --cleanup    Remove subdirectories after merging
#
# ================================================================

set -euo pipefail

TRAINING_DATA_DIR="./training_data"
CLEANUP=false

# Parse arguments
if [[ "$#" -ge 1 ]] && [[ "$1" == "--cleanup" ]]; then
    CLEANUP=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}        Merge Training Data Subdirectories                     ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Directory: ${YELLOW}${TRAINING_DATA_DIR}${NC}"
echo ""

# Track counts using simple variables
SFT_LINES=0
COMPLETION_LINES=0
DPO_LINES=0
TOTAL_LINES=0

# Find all subdirectories with jsonl files
for dir in "${TRAINING_DATA_DIR}"/*/; do
    dirname=$(basename "$dir")

    # Skip non-directory items
    if [[ ! -d "$dir" ]]; then
        continue
    fi

    # Skip hidden directories
    if [[ "$dirname" == .* ]]; then
        continue
    fi

    for jsonl_file in "${dir}"*.jsonl; do
        # Check if file exists (glob might not match)
        if [[ ! -f "$jsonl_file" ]]; then
            continue
        fi

        filename=$(basename "$jsonl_file")
        line_count=$(wc -l < "$jsonl_file" | tr -d ' ')

        echo -e "  ${GREEN}Merging${NC}: ${dirname}/${filename} → ${filename} (${line_count} lines)"

        # Append to root-level file
        cat "$jsonl_file" >> "${TRAINING_DATA_DIR}/${filename}"

        case "$filename" in
            train_sft.jsonl)
                SFT_LINES=$((SFT_LINES + line_count))
                ;;
            train_completion.jsonl)
                COMPLETION_LINES=$((COMPLETION_LINES + line_count))
                ;;
            train_dpo.jsonl)
                DPO_LINES=$((DPO_LINES + line_count))
                ;;
        esac
        TOTAL_LINES=$((TOTAL_LINES + line_count))
    done
done

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}Merge Complete!${NC}"
echo -e "================================================================${NC}"

# Show summary
echo -e "Merged ${TOTAL_LINES} total lines:"
[[ $SFT_LINES -gt 0 ]] && echo -e "  ${YELLOW}train_sft.jsonl${NC}: ${SFT_LINES} lines"
[[ $COMPLETION_LINES -gt 0 ]] && echo -e "  ${YELLOW}train_completion.jsonl${NC}: ${COMPLETION_LINES} lines"
[[ $DPO_LINES -gt 0 ]] && echo -e "  ${YELLOW}train_dpo.jsonl${NC}: ${DPO_LINES} lines"
echo ""

# Cleanup if requested
if [[ "$CLEANUP" == true ]]; then
    echo -e "${YELLOW}Cleaning up subdirectories...${NC}"
    for dir in "${TRAINING_DATA_DIR}"/*/; do
        dirname=$(basename "$dir")
        if [[ -d "$dir" ]] && [[ "$dirname" != .* ]]; then
            rm -rf "$dir"
            echo -e "  ${RED}Removed${NC}: ${dirname}/"
        fi
    done
    echo -e "${GREEN}Cleanup complete!${NC}"
fi

echo ""
echo -e "Resulting files:"
wc -l "${TRAINING_DATA_DIR}"/*.jsonl 2>/dev/null || true
