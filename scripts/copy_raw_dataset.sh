#!/bin/bash

# Find all *_raw_dataset.jsonl files in the directory (including subdirectories)
# If the file size is > 0, copy it to the target directory

# Usage: ./copy_raw_dataset.sh <source_dir> <target_dir>

if [ $# -lt 2 ]; then
    echo "Usage: $0 <source_dir> <target_dir>"
    exit 1
fi

SOURCE_DIR="$1"
TARGET_DIR="$2"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

# If target directory doesn't exist, create it
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

# Find all *_raw_dataset.jsonl files, check size > 0, then copy to target folder
find "$SOURCE_DIR" -name "*_raw_dataset.jsonl" -type f -size +0 -exec cp {} "$TARGET_DIR/" \;

echo "Finished! Non-empty *_raw_dataset.jsonl files copied to $TARGET_DIR"
