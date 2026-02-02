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
# Ensure we are dealing with an object and results exists
TOTAL=$(jq 'if type == "object" and has("results") then .results | length else 0 end' "$INPUT_FILE")
echo "Total Findings: $TOTAL"

# 2. Count by Severity
ERRORS=$(jq 'if type == "object" and has("results") then [.results[] | select(.extra.severity == "ERROR")] | length else 0 end' "$INPUT_FILE")
WARNINGS=$(jq 'if type == "object" and has("results") then [.results[] | select(.extra.severity == "WARNING")] | length else 0 end' "$INPUT_FILE")
INFOS=$(jq 'if type == "object" and has("results") then [.results[] | select(.extra.severity == "INFO")] | length else 0 end' "$INPUT_FILE")

echo "----------------------------------------------------"
echo "Severity Breakdown:"
echo "  - ERROR:    $ERRORS"
echo "  - WARNING:  $WARNINGS"
echo "  - INFO:     $INFOS"

# 3. Check ID Statistics
echo "----------------------------------------------------"
echo "Findings by Check ID:"
jq -r '.results[]?.check_id // empty' "$INPUT_FILE" | sort | uniq -c | sort -nr | awk '{printf "  %3d x %s\n", $1, $2}'

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

if [ "$ERRORS" -gt 0 ]; then
    DETAILS="CRITICAL: $ERRORS error(s) found. Patch rejected."
    jq -r '.results[]? | select(.extra.severity == "ERROR") | "\(.message // .extra.message // "Unknown")|\(.start.line // "-")"' "$INPUT_FILE" | head -5 | while IFS='|' read -r msg line; do
        if [ -n "$msg" ]; then
            if [ "$line" != "-" ] && [ -n "$line" ]; then
                DETAILS="${DETAILS}; - ${msg} (line ${line})"
            else
                DETAILS="${DETAILS}; - ${msg}"
            fi
        fi
        echo "$DETAILS"
    done | tail -1 > /tmp/comments_$$.txt
    COMMENTS=$(cat /tmp/comments_$$.txt)
    rm -f /tmp/comments_$$.txt
elif [ "$WARNINGS" -gt 0 ]; then
    DEDUCTION=$((WARNINGS*2))
    DETAILS="WARNING: $WARNINGS warning(s) found. (-$DEDUCTION)"
    jq -r '.results[]? | select(.extra.severity == "WARNING") | "\(.message // .extra.message // "Unknown")|\(.start.line // "-")"' "$INPUT_FILE" | head -5 | while IFS='|' read -r msg line; do
        if [ -n "$msg" ]; then
            if [ "$line" != "-" ] && [ -n "$line" ]; then
                DETAILS="${DETAILS}; - ${msg} (line ${line})"
            else
                DETAILS="${DETAILS}; - ${msg}"
            fi
        fi
        echo "$DETAILS"
    done | tail -1 > /tmp/comments_$$.txt
    COMMENTS=$(cat /tmp/comments_$$.txt)
    rm -f /tmp/comments_$$.txt
elif [ "$INFOS" -gt 0 ]; then
    DEDUCTION=$(echo "$INFOS * 0.5" | bc)
    DETAILS="INFO: $INFOS info finding(s). (-$DEDUCTION)"
    jq -r '.results[]? | select(.extra.severity == "INFO") | "\(.message // .extra.message // "Unknown")|\(.start.line // "-")"' "$INPUT_FILE" | head -3 | while IFS='|' read -r msg line; do
        if [ -n "$msg" ]; then
            if [ "$line" != "-" ] && [ -n "$line" ]; then
                DETAILS="${DETAILS}; - ${msg} (line ${line})"
            else
                DETAILS="${DETAILS}; - ${msg}"
            fi
        fi
        echo "$DETAILS"
    done | tail -1 > /tmp/comments_$$.txt
    COMMENTS=$(cat /tmp/comments_$$.txt)
    rm -f /tmp/comments_$$.txt
else
    COMMENTS=""
fi

if [ "$ERRORS" -gt 0 ]; then
    echo "CRITICAL: $ERRORS errors found. Patch rejected."
elif (( $(echo "$FINAL_SCORE < 60" | bc -l) )); then
    echo "WARNING: Low score. Manual audit required."
else
    echo "SUCCESS: Quality check passed."
fi

echo ""
echo "MACHINE_READABLE_OUTPUT:"
echo "SCORE:$FINAL_SCORE"
echo "COMMENTS:$COMMENTS"
