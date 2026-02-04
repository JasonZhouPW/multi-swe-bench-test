#!/bin/bash
# ============================================================================
# scripts/batch_unify_repos.sh
# Iterates through all immediate subdirectories of a given directory and 
# calls unify_repo_scripts.sh for each one.
# ============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <parent_directory>"
    exit 1
fi

PARENT_DIR="$1"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIFY_SCRIPT="$SCRIPTS_DIR/unify_repo_scripts.sh"

if [ ! -d "$PARENT_DIR" ]; then
    echo -e "${RED}Error: Directory not found: $PARENT_DIR${NC}"
    exit 1
fi

if [ ! -f "$UNIFY_SCRIPT" ]; then
    echo -e "${RED}Error: Cannot find $UNIFY_SCRIPT${NC}"
    exit 1
fi

echo -e "${YELLOW}Starting batch processing in: $PARENT_DIR${NC}"

# Find all immediate subdirectories
# Use find to get directories and avoid issues with globs if directory is empty
SUB_DIRS=$(find "$PARENT_DIR" -maxdepth 1 -mindepth 1 -type d | sort)

if [ -z "$SUB_DIRS" ]; then
    echo -e "${YELLOW}No subdirectories found in $PARENT_DIR.${NC}"
    exit 0
fi

for sub_dir in $SUB_DIRS; do
    echo -e "\n${GREEN}============================================================${NC}"
    echo -e "${GREEN}Processing directory: $sub_dir${NC}"
    echo -e "${GREEN}============================================================${NC}"
    
    # Call unify_repo_scripts.sh
    # We use a subshell to avoid exit -e in unify_repo_scripts.sh from terminating the batch
    (bash "$UNIFY_SCRIPT" "$sub_dir") || echo -e "${RED}Warning: Failed to process $sub_dir${NC}"
done

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}Batch processing completed!${NC}"
echo -e "${GREEN}============================================================${NC}"
