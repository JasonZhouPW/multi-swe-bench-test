#!/bin/bash

# analyze_patch.sh - Semgrep Result Analyzer & Rating System
# Usage: ./analyze_patch.sh [json_file]

INPUT_FILE=${1:-out.txt}

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."
    exit 1
fi

echo "===================================================="
echo "          Semgrep Patch Analysis Report             "
echo "===================================================="
echo "Analyzing: $INPUT_FILE"

# 1. Total findings
TOTAL=$(jq '.results | length' "$INPUT_FILE")
echo "Total Findings: $TOTAL"

# 2. Count by Severity
ERRORS=$(jq '[.results[] | select(.extra.severity == "ERROR")] | length' "$INPUT_FILE")
WARNINGS=$(jq '[.results[] | select(.extra.severity == "WARNING")] | length' "$INPUT_FILE")
INFOS=$(jq '[.results[] | select(.extra.severity == "INFO")] | length' "$INPUT_FILE")

echo "----------------------------------------------------"
echo "Severity Breakdown:"
echo "  - ERROR:    $ERRORS"
echo "  - WARNING:  $WARNINGS"
echo "  - INFO:     $INFOS"

# 3. Check ID Statistics
echo "----------------------------------------------------"
echo "Findings by Check ID:"
jq -r '.results[].check_id' "$INPUT_FILE" | sort | uniq -c | sort -nr | awk '{printf "  %3d x %s\n", $1, $2}'

# 4. Rating System
# Base Score: 100
# Deductions: Error=10, Warning=2, Info=0.5
SCORE_DEDUCTION=$(echo "($ERRORS * 10) + ($WARNINGS * 2) + ($INFOS * 0.5)" | bc)
FINAL_SCORE=$(echo "100 - $SCORE_DEDUCTION" | bc)

# Clamp score to 0
if (( $(echo "$FINAL_SCORE < 0" | bc -l) )); then
    FINAL_SCORE=0
fi

# Determine Grade
GRADE=""
COLOR=""
if (( $(echo "$FINAL_SCORE >= 90" | bc -l) )); then
    GRADE="S (Excellent)"
elif (( $(echo "$FINAL_SCORE >= 80" | bc -l) )); then
    GRADE="A (Good)"
elif (( $(echo "$FINAL_SCORE >= 70" | bc -l) )); then
    GRADE="B (Fair)"
elif (( $(echo "$FINAL_SCORE >= 60" | bc -l) )); then
    GRADE="C (Weak)"
else
    GRADE="F (Unsafe)"
fi

echo "----------------------------------------------------"
echo "Final Score: $FINAL_SCORE / 100"
echo "Patch Grade: $GRADE"
echo "===================================================="

# Summary Recommendation
if [ "$ERRORS" -gt 0 ]; then
    echo "CRITICAL: $ERRORS errors found. Patch rejected."
elif (( $(echo "$FINAL_SCORE < 60" | bc -l) )); then
    echo "WARNING: Low score. Manual audit required."
else
    echo "SUCCESS: Quality check passed."
fi
