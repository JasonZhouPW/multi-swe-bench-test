#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Worker scripts
AUTO_ADD_IMPORT="$SCRIPT_DIR/../data_pipeline/auto_add_import.sh"
CREATE_ORG_DIR="$SCRIPT_DIR/../data_pipeline/create_org_dir.sh"
#GEN_INSTANCE="$SCRIPT_DIR/../data_pipeline/gen_instance_from_dataset_golang.sh"
chmod +x "$AUTO_ADD_IMPORT" "$CREATE_ORG_DIR"

echo "🚀 Starting unified pipeline"

########################################
# Parse input argument
########################################
INPUT=${1:-""}

if [[ -z "$INPUT" ]]; then
    echo "❌ Usage: $0 <raw_dataset_file | dataset_directory>"
    exit 1
fi

########################################
# Detect file or directory
########################################
FILES=()

if [[ -f "$INPUT" ]]; then
    # Case 1: specific file provided
    echo "📘 Input is a file: $INPUT"
    FILES+=("$INPUT")
elif [[ -d "$INPUT" ]]; then
    # Case 2: input is a directory
    echo "📂 Input is a directory: $INPUT"
    # Recursively find all *raw_dataset*.jsonl files in directory and subdirectories
    while IFS= read -r f; do FILES+=("$f"); done < <(find "$INPUT" -type f -name "*raw_dataset*.jsonl" 2>/dev/null | sort)

    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "❌ No *raw_dataset*.jsonl files found in directory: $INPUT"
        exit 1
    fi
else
    echo "❌ Invalid path: $INPUT"
    exit 1
fi

## Initialize multi-swe-bench repo structure
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/c"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/cpp"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/csharp"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/golang"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/html"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/java"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/javascript"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/kotlin"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/php"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/python"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/rust"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/ruby"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/scala"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/swift"
mkdir -p "$PROJ_ROOT/multi-swe-bench/harness/repos/typescript"

# Check if __init__.py exists in each repo directory
INIT_FILE="$PROJ_ROOT/multi-swe-bench/harness/repos/__init__.py"
if [ ! -f "$INIT_FILE" ]; then
    cat <<EOF > "$INIT_FILE"
from multi_swe_bench.harness.repos.c import *
from multi_swe_bench.harness.repos.cpp import *
from multi_swe_bench.harness.repos.golang import *
from multi_swe_bench.harness.repos.java import *
from multi_swe_bench.harness.repos.javascript import *
from multi_swe_bench.harness.repos.python import *
from multi_swe_bench.harness.repos.rust import *
from multi_swe_bench.harness.repos.typescript import *
from multi_swe_bench.harness.repos.ruby import *
from multi_swe_bench.harness.repos.php import *
from multi_swe_bench.harness.repos.swift import *
from multi_swe_bench.harness.repos.kotlin import *
from multi_swe_bench.harness.repos.scala import *
from multi_swe_bench.harness.repos.csharp import *
from multi_swe_bench.harness.repos.html import *
EOF
fi

########################################
# Process all matched files
########################################
for RAW_FILE in "${FILES[@]}"; do

    LINE=$(head -n 1 "$RAW_FILE")
    LANG_RAW=$(echo "$LINE" | sed -n 's/.*"language": *"\([^"]*\)".*/\1/p')
    LANG_RAW=$(echo "$LANG_RAW" | tr 'A-Z' 'a-z')
    if [ "$LANG_RAW" == "go" ]; then
        LANG_RAW="golang"
    fi
    if [ "$LANG_RAW" == "c++" ]; then
        LANG_RAW="cpp"
    fi
    if [ -z "$LANG_RAW" ]; then
        LANG_RAW="golang"
    fi
    echo "🔍 Detected language: $LANG_RAW"
    GEN_INSTANCE="$SCRIPT_DIR/../data_pipeline/gen_instance_from_dataset_${LANG_RAW}.sh"
    echo " Using GEN_INSTANCE: $GEN_INSTANCE"
    chmod +x "$GEN_INSTANCE"

    FILENAME=$(basename "$RAW_FILE")
    DIRNAME=$(dirname "$RAW_FILE")
    TEMP_FILE="${DIRNAME}/temp_single_${FILENAME}"

    echo "=============================================="
    echo "📘 Processing raw dataset: $FILENAME"
    echo "=============================================="

    # Extract only first line
    echo "📌 Extracting first record → $TEMP_FILE"
    head -n 1 "$RAW_FILE" > "$TEMP_FILE"

    echo "🔧 Step 1: auto_add_import.sh..."
    "$AUTO_ADD_IMPORT" "$TEMP_FILE"
    echo ""

    echo "📂 Step 2: create_org_dir.sh..."
    "$CREATE_ORG_DIR" "$TEMP_FILE"
    echo ""

     echo "🧬 Step 3: gen_instance_from_dataset_$LANG_RAW.sh..."
     if "$GEN_INSTANCE" "$TEMP_FILE"; then
         echo "✅ Instance generation successful"
     else
         echo "❌ Instance generation failed for $RAW_FILE"
         # Continue to next file
     fi
     echo ""

    echo "🧹 Cleaning temp file: $TEMP_FILE"
    rm -f "$TEMP_FILE"
    echo "✔ Temp file removed."

    echo "🎉 Finished processing: $FILENAME"
    echo ""

    echo "========================================="
    echo "🚀 Finally: Building dataset..."
    echo "========================================="

    # ---- Safe derive BASE_NAME ----
    if [ -z "${BASE_NAME-}" ]; then
        RAW_BASENAME=$(basename "$RAW_FILE")
        BASE_NAME="${RAW_BASENAME%%_raw_dataset.jsonl}"
    fi
    # --------------------------------

    "$SCRIPT_DIR/../data_pipeline/build_dataset.sh" "$RAW_FILE" 

    ##########################################
    # Derive dataset filename (multiple entries merged in one file)
    ##########################################
    DATASET_FILE="${BASE_NAME}_dataset.jsonl"
    DATASET_PATH="$PROJ_ROOT/data/datasets/$DATASET_FILE"

    if [ ! -f "$DATASET_PATH" ]; then
        echo "❌ Error: dataset file not generated: $DATASET_PATH"
        # exit 1 # continue to next file
    else 
        echo "✅ Dataset generated: $DATASET_PATH"    
    fi


    echo "Remove all docker images"
    # 1. Stop all docker containers
    docker container stop $(docker ps -aq) || true
    # 2. Remove all docker containers
    docker container rm $(docker ps -aq) || true
    # 3. Remove all docker images
    docker rmi $( docker images --format "table {{.Repository}}\t{{.ID}}" | grep -v "mswebench/nix_swe" | awk '{print $2}') || true
done

##########################################
# Finally: Build dataset (supports multiple records)
##########################################
# echo "========================================="
# echo "🚀 Finally: Building dataset..."
# echo "========================================="

# # ---- Safe derive BASE_NAME ----
# if [ -z "${BASE_NAME-}" ]; then
#     RAW_BASENAME=$(basename "$RAW_FILE")
#     BASE_NAME="${RAW_BASENAME%%_raw_dataset.jsonl}"
# fi
# # --------------------------------

# ./data_pipeline/build_dataset.sh "$RAW_FILE"

# ##########################################
# # Derive dataset filename (multiple entries merged in one file)
# ##########################################
# DATASET_FILE="${BASE_NAME}_dataset.jsonl"
# DATASET_PATH="./data/datasets/$DATASET_FILE"

# if [ ! -f "$DATASET_PATH" ]; then
#     echo "❌ Error: dataset file not generated: $DATASET_PATH"
#     exit 1
# fi

# echo "✅ Dataset generated: $DATASET_PATH"

echo "🏁 All selected raw_dataset files processed successfully!"