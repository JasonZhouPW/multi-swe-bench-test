#!/bin/bash

# ============================================================================
# Filter *_raw_dataset.jsonl files
# Filter records based on user input keywords (can be multiple) or category/label
# Output to specified output directory
# ============================================================================

set -e

# Show usage instructions
function show_usage() {
    echo "Usage: $0 -i <input_dir> -o <output_dir> [options]"
    echo ""
    echo "Required arguments:"
    echo "  -i, --input-dir     Specify input directory path (contains *_raw_dataset.jsonl files)"
    echo "  -o, --output-dir    Specify output directory path"
    echo ""
    echo "Filter options (must specify at least one):"
    echo "  -k, --keywords      Filter by (comma-separated keywords, search in title and body)"
    echo "  -c, --category      Filter by label/category (comma-separated categories)"
    echo ""
    echo "Optional arguments:"
    echo "  -m, --match-mode    Match mode: 'any' (default, match any) or 'all' (match all)"
    echo "  -s, --case-sensitive  Case sensitive (default is not case sensitive)"
    echo "  -p, --min-patch-size  Specify minimum patch size (unit: bytes, default 0 no limit)"
    echo "  -pt, --min-test-patch-size Specify minimum test patch size (unit: bytes, default 0 no limit)"
    echo "  -h, --help          Show help information"
    echo ""
    echo "Examples:"
    echo "  # Filter by keyword (match records containing 'fix' or 'bug' in title or body)"
    echo "  $0 -i ./raw_ds -o ./filtered -k 'fix,bug'"
    echo ""
    echo "  # Filter by category/label"
    echo "  $0 -i ./raw_ds -o ./filtered -c 'bug,enhancement'"
    echo ""
    echo "  # Use both keyword and category filter (must satisfy both)"
    echo "  $0 -i ./raw_ds -o ./filtered -k 'fix' -c 'bug' -m all"
    echo ""
    exit 1
}

# Default values
INPUT_DIR=""
OUTPUT_DIR=""
KEYWORDS=""
CATEGORIES=""
MATCH_MODE="any"
CASE_SENSITIVE=false
MIN_PATCH_SIZE=0
MIN_TEST_PATCH_SIZE=0

# Parse command line parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input-dir)
            INPUT_DIR="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -k|--keywords)
            KEYWORDS="$2"
            shift 2
            ;;
        -c|--category)
            CATEGORIES="$2"
            shift 2
            ;;
        -m|--match-mode)
            MATCH_MODE="$2"
            shift 2
            ;;
        -s|--case-sensitive)
            CASE_SENSITIVE=true
            shift
            ;;
        -p|--min-patch-size)
            MIN_PATCH_SIZE="$2"
            shift 2
            ;;
        -pt|--min-test-patch-size)
            MIN_TEST_PATCH_SIZE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Error: Unknown option $1"
            show_usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$INPUT_DIR" ]]; then
    echo "Error: Please specify input directory (-i)"
    show_usage
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: Please specify output directory (-o)"
    show_usage
fi

# If no filter conditions specified, provide interactive menu
if [[ -z "$KEYWORDS" && -z "$CATEGORIES" ]]; then
    echo "============================================"
    echo "No filter conditions detected, please select a preset category:"
    echo "1. New Feature"
    echo "2. Bug Fix"
    echo "3. Edge Case & Robustness"
    echo "4. Performance Improvements"
    echo "5. Refactor"
    echo "6. Exit"
    echo "============================================"

    choice=""
    while [[ ! "$choice" =~ ^[1-6]$ ]]; do
        read -p "Please enter option [1-6]: " choice
    done

    case $choice in
        1) CATEGORIES="new feature";;
        2) CATEGORIES="fix bug";;
        3) CATEGORIES="edge case & robustness";;
        4) CATEGORIES="performance improvements";;
        5) CATEGORIES="refactor";;
        6) exit 0;;
    esac

    echo ""
    read -p "Do you need additional keyword filtering? (press Enter to skip): " input_kw
    if [[ -n "$input_kw" ]]; then
        KEYWORDS="$input_kw"
    fi
fi

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory does not exist: $INPUT_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Function: Calculate code patch size (excluding documentation files)
# ============================================================================
calculate_code_patch_size() {
    local patch="$1"

    # Use awk to parse diff and exclude documentation files. Logic from filter_large_patches.sh
    echo "$patch" | awk '
    BEGIN {
        in_doc = 0
        hunk_size = 0
        total = 0
        # Documentation extensions
        split(".md .txt .rst .adoc .asciidoc .readme README CHANGELOG CONTRIBUTING LICENSE NOTICE AUTHORS .gitignore .dockerignore", exts, " ")
        for (i in exts) doc_map[exts[i]] = 1
    }
    /^diff --git / {
        split($0, parts, " ")
        filepath = parts[3]
        sub(/^a\//, "", filepath)

        is_doc = 0
        for (ext in doc_map) { if (filepath ~ ext "$") { is_doc = 1; break } }
        if (tolower(filepath) ~ /readme|changelog|contributing|license|notice|authors|\.gitignore|\.dockerignore/) {
            is_doc = 1
        }

        if (in_doc == 0 && hunk_size > 0) total += hunk_size
        in_doc = is_doc
        hunk_size = 0
    }
    /^@@/ {
        if (in_doc == 0 && hunk_size > 0) total += hunk_size
        hunk_size = 0
    }
    /^[+-]/ {
        if (in_doc == 0) hunk_size += length($0) - 1
    }
    END {
        if (in_doc == 0 && hunk_size > 0) total += hunk_size
        print total
    }
    '
}

# ============================================================================
# Special presets: When category is "new feature" or "fix bug", automatically use method 3 (keyword + label combination filtering)
# ============================================================================
USE_PRESET_MODE=false

handle_special_presets() {
    local categories_lower=$(echo "$CATEGORIES" | tr '[:upper:]' '[:lower:]')

    # Check if contains "new feature" or "new-feature" or "newfeature"
    if [[ "$categories_lower" == *"new feature"* ]] || \
       [[ "$categories_lower" == *"new-feature"* ]] || \
       [[ "$categories_lower" == *"newfeature"* ]]; then

        echo "============================================"
        echo "Detected 'new feature' preset, enabling combined filter mode"
        echo "============================================"

        USE_PRESET_MODE=true

        # Set new feature related keywords (search in title and body)
        local new_feature_keywords="add,implement,introduce,support,feature,enable"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$new_feature_keywords"
        else
            KEYWORDS="$KEYWORDS,$new_feature_keywords"
        fi

        # Set new feature related labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/new[- ]?feature,?//gi' | sed 's/,$//' | sed 's/^,//')
        local new_feature_labels="enhancement,feature"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$new_feature_labels"
        else
            CATEGORIES="$CATEGORIES,$new_feature_labels"
        fi

        echo "Extended keywords: $KEYWORDS (match any one)"
        echo "Extended Categories: $CATEGORIES (match any one)"
        echo "Combination mode: Keyword match AND Label match"
        echo "============================================"
    fi

    # Check if contains "fix bug" or "fix-bug" or "fixbug" or "bugfix"
    if [[ "$categories_lower" == *"fix bug"* ]] || \
       [[ "$categories_lower" == *"fix-bug"* ]] || \
       [[ "$categories_lower" == *"fixbug"* ]] || \
       [[ "$categories_lower" == *"bugfix"* ]] || \
       [[ "$categories_lower" == *"bug fix"* ]]; then

        echo "============================================"
        echo "Detected 'fix bug' preset, enabling combined filter mode"
        echo "============================================"

        USE_PRESET_MODE=true

        # Set fix bug related keywords (search in title and body)
        local fix_bug_keywords="fix,fixed,fixes,fixing,resolve,resolved,resolves,patch,repair,correct,bug,issue,error,problem"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$fix_bug_keywords"
        else
            KEYWORDS="$KEYWORDS,$fix_bug_keywords"
        fi

        # Set fix bug related labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(fix[- ]?bug|bug[- ]?fix),?//gi' | sed 's/,$//' | sed 's/^,//')
        local fix_bug_labels="bug,bugfix,fix,hotfix,patch"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$fix_bug_labels"
        else
            CATEGORIES="$CATEGORIES,$fix_bug_labels"
        fi

        echo "Extended keywords: $KEYWORDS (match any one)"
        echo "Extended Categories: $CATEGORIES (match any one)"
        echo "Combination mode: Keyword match AND Label match"
        echo "============================================"
    fi

    # Check if contains "edge case & robustness" or its variants
    if [[ "$categories_lower" == *"edge case"* ]] || \
       [[ "$categories_lower" == *"edge-case"* ]] || \
       [[ "$categories_lower" == *"edgecase"* ]] || \
       [[ "$categories_lower" == *"robustness"* ]] || \
       [[ "$categories_lower" == *"corner case"* ]] || \
       [[ "$categories_lower" == *"edge case & robustness"* ]] || \
       [[ "$categories_lower" == *"edge case and robustness"* ]]; then

        echo "============================================"
        echo "Detected 'edge case & robustness' preset, enabling combined filter mode"
        echo "============================================"

        USE_PRESET_MODE=true

        # Set edge case/robustness related keywords (search in title and body)
        local edge_case_keywords="edge case,corner case,boundary,edge,corner,overflow,underflow,null,empty,invalid,unexpected,exception,handle,handling,validation,validate,check,guard,defensive,robust,robustness,fallback,graceful,safety,safe"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$edge_case_keywords"
        else
            KEYWORDS="$KEYWORDS,$edge_case_keywords"
        fi

        # Set edge case/robustness related labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(edge[- ]?case[- &]*robustness|edge[- ]?case[- ]*and[- ]*robustness|edge[- ]?case|robustness|corner[- ]?case),?//gi' | sed 's/,$//' | sed 's/^,//')
        local edge_case_labels="edge-case,corner-case,robustness,validation,bug,bugfix"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$edge_case_labels"
        else
            CATEGORIES="$CATEGORIES,$edge_case_labels"
        fi

        echo "Extended keywords: $KEYWORDS (match any one)"
        echo "Extended Categories: $CATEGORIES (match any one)"
        echo "Combination mode: Keyword match AND Label match"
        echo "============================================"
    fi

    # Check if contains "performance improvements" or its variants
    if [[ "$categories_lower" == *"performance"* ]] || \
       [[ "$categories_lower" == *"optimization"* ]] || \
       [[ "$categories_lower" == *"improvement"* ]]; then

        echo "============================================"
        echo "Detected 'performance improvements' preset, enabling combined filter mode"
        echo "============================================"

        USE_PRESET_MODE=true

        # Set performance optimization related keywords (search in title and body)
        local perf_keywords="performance,performant,optimize,optimization,optimized,efficient,efficiency,speed,fast,faster,slow,latency,throughput,memory,leak,resource,scalability,scale,bottleneck"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$perf_keywords"
        else
            KEYWORDS="$KEYWORDS,$perf_keywords"
        fi

        # Set performance optimization related labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(performance|optimization|improvement|efficiency),?//gi' | sed 's/,$//' | sed 's/^,//')
        local perf_labels="performance,optimization,enhancement,speed,memory,efficiency"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$perf_labels"
        else
            CATEGORIES="$CATEGORIES,$perf_labels"
        fi

        echo "Extended keywords: $KEYWORDS (match any one)"
        echo "Extended Categories: $CATEGORIES (match any one)"
        echo "Combination mode: Keyword match AND Label match"
        echo "============================================"
    fi

    # Check if contains "refactor" or its variants
    if [[ "$categories_lower" == *"refactor"* ]] || \
       [[ "$categories_lower" == *"cleanup"* ]] || \
       [[ "$categories_lower" == *"reorganize"* ]]; then

        echo "============================================"
        echo "Detected 'refactor' preset, enabling combined filter mode"
        echo "============================================"

        USE_PRESET_MODE=true

        # Set refactoring related keywords (search in title and body)
        local refactor_keywords="refactor,refactoring,refactored,clean,cleanup,reorganize,rename,restructure,simplify,simplification,extract,move,migrate,migration,polish,style"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$refactor_keywords"
        else
            KEYWORDS="$KEYWORDS,$refactor_keywords"
        fi

        # Set refactoring related labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(refactor|cleanup|reorganize),?//gi' | sed 's/,$//' | sed 's/^,//')
        local refactor_labels="refactor,cleanup,internal,internal-ref-reffactor,documentation,style"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$refactor_labels"
        else
            CATEGORIES="$CATEGORIES,$refactor_labels"
        fi

        echo "Extended keywords: $KEYWORDS (match any one)"
        echo "Extended Categories: $CATEGORIES (match any one)"
        echo "Combination mode: Keyword match AND Label match"
        echo "============================================"
    fi
}

# Apply special preset handling
handle_special_presets

echo "============================================"
echo "Filtering JSONL files"
echo "============================================"
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Keywords: ${KEYWORDS:-none}"
echo "Categories: ${CATEGORIES:-none}"
echo "Match mode: $MATCH_MODE"
echo "Case sensitive: $CASE_SENSITIVE"
echo "Min patch size: $MIN_PATCH_SIZE"
echo "Min test patch size: $MIN_TEST_PATCH_SIZE"
echo "============================================"

# ============================================================================
# Function: Build jq filter expression
# ============================================================================
build_jq_filter() {
    local keyword_filter=""
    local category_filter=""

    # Determine keyword and label internal match mode
    # Preset mode: internal uses any, combination uses all
    # Normal mode: both use user-specified MATCH_MODE
    local internal_kw_mode="$MATCH_MODE"
    local internal_cat_mode="$MATCH_MODE"
    local combine_mode="$MATCH_MODE"

    if [[ "$USE_PRESET_MODE" == "true" ]]; then
        internal_kw_mode="any"   # Keywords use or
        internal_cat_mode="any"  # Labels use or
        combine_mode="all"       # Keywords and labels use and
    fi

    # Build keyword filter conditions
    if [[ -n "$KEYWORDS" ]]; then
        IFS=',' read -ra KW_ARRAY <<< "$KEYWORDS"
        local kw_conditions=()
        for kw in "${KW_ARRAY[@]}"; do
            # Remove leading/trailing whitespace
            kw=$(echo "$kw" | xargs)
            if [[ "$CASE_SENSITIVE" == "false" ]]; then
                # Case insensitive: convert fields and keywords to lowercase
                kw_conditions+=("(((.title // \"\") | ascii_downcase | contains(\"$(echo "$kw" | tr '[:upper:]' '[:lower:]')\")) or ((.body // \"\") | ascii_downcase | contains(\"$(echo "$kw" | tr '[:upper:]' '[:lower:]')\")))")
            else
                kw_conditions+=("(((.title // \"\") | contains(\"$kw\")) or ((.body // \"\") | contains(\"$kw\")))")
            fi
        done

        if [[ "$internal_kw_mode" == "all" ]]; then
            keyword_filter=$(printf "%s" "${kw_conditions[0]}")
            for ((i=1; i<${#kw_conditions[@]}; i++)); do
                keyword_filter="$keyword_filter and ${kw_conditions[$i]}"
            done
        else
            keyword_filter=$(printf "%s" "${kw_conditions[0]}")
            for ((i=1; i<${#kw_conditions[@]}; i++)); do
                keyword_filter="$keyword_filter or ${kw_conditions[$i]}"
            done
        fi
    fi

    # Build category/label filter conditions
    if [[ -n "$CATEGORIES" ]]; then
        IFS=',' read -ra CAT_ARRAY <<< "$CATEGORIES"
        local cat_conditions=()
        for cat in "${CAT_ARRAY[@]}"; do
            # Remove cat leading/trailing whitespace
            cat=$(echo "$cat" | xargs)
            if [[ "$CASE_SENSITIVE" == "false" ]]; then
                cat_conditions+=("((.labels // []) | map((if type == \"object\" then .name else . end) // \"\" | ascii_downcase) | any(. | contains(\"$(echo "$cat" | tr '[:upper:]' '[:lower:]')\")))")
            else
                cat_conditions+=("((.labels // []) | map((if type == \"object\" then .name else . end) // \"\") | any(. | contains(\"$cat\")))")
            fi
        done

        if [[ "$internal_cat_mode" == "all" ]]; then
            category_filter=$(printf "%s" "${cat_conditions[0]}")
            for ((i=1; i<${#cat_conditions[@]}; i++)); do
                category_filter="$category_filter and ${cat_conditions[$i]}"
            done
        else
            category_filter=$(printf "%s" "${cat_conditions[0]}")
            for ((i=1; i<${#cat_conditions[@]}; i++)); do
                category_filter="$category_filter or ${cat_conditions[$i]}"
            done
        fi
    fi

    # Combine filter conditions
    if [[ -n "$keyword_filter" && -n "$category_filter" ]]; then
        if [[ "$combine_mode" == "all" ]]; then
            echo "($keyword_filter) and ($category_filter)"
        else
            echo "($keyword_filter) or ($category_filter)"
        fi
    elif [[ -n "$keyword_filter" ]]; then
        echo "$keyword_filter"
    else
        echo "$category_filter"
    fi
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq not installed. Please install jq first: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Build filter expression
JQ_FILTER=$(build_jq_filter)
echo "JQ filter expression: $JQ_FILTER"
echo "============================================"

# Statistics
total_files=0
total_input_records=0
total_output_records=0

# Find all *_raw_dataset.jsonl files
for jsonl_file in "$INPUT_DIR"/*_raw_dataset.jsonl; do
    if [[ ! -f "$jsonl_file" ]]; then
        echo "Warning: No *_raw_dataset.jsonl files found in $INPUT_DIR"
        break
    fi

    ((total_files++)) || true

    filename=$(basename "$jsonl_file")
    output_file="$OUTPUT_DIR/$filename"

    echo "Processing: $filename"

    # Count input records
    input_count=$(wc -l < "$jsonl_file" | xargs)
    ((total_input_records += input_count)) || true

    # Process line by line (to filter by patch size)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # 1. First try JQ filtering
        filtered_line=$(echo "$line" | jq -c "select($JQ_FILTER)")

        if [[ -n "$filtered_line" ]]; then
            # 2. If MIN_PATCH_SIZE limit exists, calculate patch size
            pass_patch=true
            if [[ "$MIN_PATCH_SIZE" -gt 0 ]]; then
                patch_content=$(echo "$filtered_line" | jq -r '.fix_patch // empty')
                if [[ -n "$patch_content" ]]; then
                    code_patch_size=$(calculate_code_patch_size "$patch_content")
                    if [[ "$code_patch_size" -le "$MIN_PATCH_SIZE" ]]; then
                        pass_patch=false
                    fi
                else
                    pass_patch=false
                fi
            fi

            # 3. If MIN_TEST_PATCH_SIZE limit exists, calculate test patch size
            if [[ "$pass_patch" == "true" && "$MIN_TEST_PATCH_SIZE" -gt 0 ]]; then
                test_patch_content=$(echo "$filtered_line" | jq -r '.test_patch // empty')
                if [[ -n "$test_patch_content" ]]; then
                    test_code_patch_size=$(calculate_code_patch_size "$test_patch_content")
                    if [[ "$test_code_patch_size" -le "$MIN_TEST_PATCH_SIZE" ]]; then
                        pass_patch=false
                    fi
                else
                    pass_patch=false
                fi
            fi

            if [[ "$pass_patch" == "true" ]]; then
                echo "$filtered_line" >> "$output_file"
            fi
        fi
    done < "$jsonl_file"

    # Count output records
    if [[ -f "$output_file" ]]; then
        output_count=$(wc -l < "$output_file" | xargs)
    else
        output_count=0
    fi
    ((total_output_records += output_count)) || true

    echo "  Input: $input_count records, Output: $output_count records"

    # If output file exists and is empty, delete it
    if [[ -f "$output_file" && ! -s "$output_file" ]]; then
        rm "$output_file"
        echo "  (Output is empty, deleted)"
    fi
done

echo "============================================"
echo "Processing completed!"
echo "Processed files: $total_files"
echo "Total input records: $total_input_records"
echo "Total output records: $total_output_records"
echo "Output directory: $OUTPUT_DIR"
echo "============================================"
