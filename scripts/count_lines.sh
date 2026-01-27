#!/bin/bash

# Check if directory is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <directory> [extension]"
    echo "Example: $0 . py"
    exit 1
fi

SEARCH_DIR=$1
EXT=$2

if [ -n "$EXT" ]; then
    echo "Counting lines for *.$EXT files in $SEARCH_DIR..."
    find "$SEARCH_DIR" -type f -name "*.$EXT" -exec wc -l {} + | sort -rn
else
    echo "Counting lines for all files in $SEARCH_DIR..."
    find "$SEARCH_DIR" -type f -exec wc -l {} + | sort -rn
fi
