#!/usr/bin/env bash

# Script to run semgrep scan on files modified in a patch
# Usage: ./semgrep_scan.sh [patch_file] [output_file]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PATCH_FILE="${1}"
OUTPUT_FILE="${2}"

if [ -z "$PATCH_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo -e "${RED}Usage: $0 [patch_file] [output_file]${NC}"
    exit 1
fi

# 1. Check if semgrep is installed
if ! command -v semgrep &> /dev/null; then
    echo -e "${YELLOW}Semgrep not found. Attempting to install...${NC}"
    
    # Check for pip
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        echo -e "${RED}Error: pip not found. Please install python/pip first.${NC}"
        exit 1
    fi
    
    PIP_CMD="pip"
    if command -v pip3 &> /dev/null; then
        PIP_CMD="pip3"
    fi
    
    echo -e "${GREEN}Installing semgrep via ${PIP_CMD}...${NC}"
    $PIP_CMD install semgrep
fi

# Double check installation
if ! command -v semgrep &> /dev/null; then
    echo -e "${RED}Error: Semgrep installation failed or not in PATH.${NC}"
    exit 1
fi

echo -e "${GREEN}Semgrep is ready.${NC}"

# 2. Check if patch file exists
if [ ! -f "$PATCH_FILE" ]; then
    echo -e "${RED}Error: Patch file not found: $PATCH_FILE${NC}"
    exit 1
fi

# 3. Extract files from patch and run semgrep
echo -e "${YELLOW}Starting scan for files in ${PATCH_FILE}...${NC}"

# Extract file paths from "+++ b/path/to/file" lines
FILES=$(grep "^+++ b/" "$PATCH_FILE" | cut -c 7-)

if [ -z "$FILES" ]; then
    echo -e "${YELLOW}No files found in patch to scan.${NC}"
    echo "[]" > "$OUTPUT_FILE"
    exit 0
fi

echo -e "Files to scan:\n${FILES}"

# Run semgrep scan
# We use xargs to pass the file list to semgrep
# Redirect output to the specified file
echo "$FILES" | xargs semgrep scan --config auto --json --output "$OUTPUT_FILE"

echo -e "${GREEN}Scan completed. Results saved to: ${OUTPUT_FILE}${NC}"
