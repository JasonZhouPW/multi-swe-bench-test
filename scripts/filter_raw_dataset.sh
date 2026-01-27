#!/bin/bash

# ============================================================================
# 过滤 *_raw_dataset.jsonl 文件
# 根据用户输入的关键字(可以是多个)或 category(label) 过滤出符合条件的记录
# 输出到指定的 output dir 中
# ============================================================================

set -e

# 显示使用说明
function show_usage() {
    echo "Usage: $0 -i <input_dir> -o <output_dir> [options]"
    echo ""
    echo "Required arguments:"
    echo "  -i, --input-dir     指定输入文件夹路径 (包含 *_raw_dataset.jsonl 文件)"
    echo "  -o, --output-dir    指定输出文件夹路径"
    echo ""
    echo "Filter options (至少指定一个):"
    echo "  -k, --keywords      关键字过滤 (逗号分隔多个关键字, 在 title 和 body 中搜索)"
    echo "  -c, --category      按 label/category 过滤 (逗号分隔多个 category)"
    echo ""
    echo "Optional arguments:"
    echo "  -m, --match-mode    匹配模式: 'any' (默认, 匹配任意一个) 或 'all' (匹配所有)"
    echo "  -s, --case-sensitive  区分大小写 (默认不区分)"
    echo "  -p, --min-patch-size  指定最小 patch 大小 (单位: bytes, 默认 0 不限制)"
    echo "  -h, --help          显示帮助信息"
    echo ""
    echo "Examples:"
    echo "  # 按关键字过滤 (匹配 title 或 body 中包含 'fix' 或 'bug' 的记录)"
    echo "  $0 -i ./raw_ds -o ./filtered -k 'fix,bug'"
    echo ""
    echo "  # 按 category/label 过滤"
    echo "  $0 -i ./raw_ds -o ./filtered -c 'bug,enhancement'"
    echo ""
    echo "  # 同时使用关键字和 category 过滤 (需要同时满足)"
    echo "  $0 -i ./raw_ds -o ./filtered -k 'fix' -c 'bug' -m all"
    echo ""
    exit 1
}

# 默认值
INPUT_DIR=""
OUTPUT_DIR=""
KEYWORDS=""
CATEGORIES=""
MATCH_MODE="any"
CASE_SENSITIVE=false
MIN_PATCH_SIZE=0

# 解析命令行参数
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
        -h|--help)
            show_usage
            ;;
        *)
            echo "Error: Unknown option $1"
            show_usage
            ;;
    esac
done

# 验证必需参数
if [[ -z "$INPUT_DIR" ]]; then
    echo "Error: 请指定输入文件夹 (-i)"
    show_usage
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: 请指定输出文件夹 (-o)"
    show_usage
fi

# 如果未指定过滤条件，提供交互式菜单
if [[ -z "$KEYWORDS" && -z "$CATEGORIES" ]]; then
    echo "============================================"
    echo "未检测到过滤条件，请选择预设类别:"
    echo "1. New Feature (新功能)"
    echo "2. Bug Fix (Bug修复)"
    echo "3. Edge Case & Robustness (边界情况与健壮性)"
    echo "4. Performance Improvements (性能优化)"
    echo "5. 退出"
    echo "============================================"
    
    choice=""
    while [[ ! "$choice" =~ ^[1-5]$ ]]; do
        read -p "请输入选项 [1-5]: " choice
    done
    
    case $choice in
        1) CATEGORIES="new feature";;
        2) CATEGORIES="fix bug";;
        3) CATEGORIES="edge case & robustness";;
        4) CATEGORIES="performance improvements";;
        5) exit 0;;
    esac
    
    echo ""
    read -p "是否需要额外关键字过滤? (直接回车跳过): " input_kw
    if [[ -n "$input_kw" ]]; then
        KEYWORDS="$input_kw"
    fi
fi

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: 输入文件夹不存在: $INPUT_DIR"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# ============================================================================
# 函数: 计算代码补丁大小 (不包含文档文件)
# ============================================================================
calculate_code_patch_size() {
    local patch="$1"
    
    # 使用 awk 来解析 diff 并排除文档。逻辑参考 filter_large_patches.sh
    echo "$patch" | awk '
    BEGIN {
        in_doc = 0
        hunk_size = 0
        total = 0
        # 文档扩展名
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
# 特殊预设: 当 category 为 "new feature" 或 "fix bug" 时，自动使用方法3(关键字+label组合过滤)
# ============================================================================
USE_PRESET_MODE=false

handle_special_presets() {
    local categories_lower=$(echo "$CATEGORIES" | tr '[:upper:]' '[:lower:]')
    
    # 检查是否包含 "new feature" 或 "new-feature" 或 "newfeature"
    if [[ "$categories_lower" == *"new feature"* ]] || \
       [[ "$categories_lower" == *"new-feature"* ]] || \
       [[ "$categories_lower" == *"newfeature"* ]]; then
        
        echo "============================================"
        echo "检测到 'new feature' 预设，自动启用组合过滤模式"
        echo "============================================"
        
        USE_PRESET_MODE=true
        
        # 设置新功能相关的关键字 (在 title 和 body 中搜索)
        local new_feature_keywords="add,implement,introduce,support,feature,enable"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$new_feature_keywords"
        else
            KEYWORDS="$KEYWORDS,$new_feature_keywords"
        fi
        
        # 设置新功能相关的 labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/new[- ]?feature,?//gi' | sed 's/,$//' | sed 's/^,//')
        local new_feature_labels="enhancement,feature"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$new_feature_labels"
        else
            CATEGORIES="$CATEGORIES,$new_feature_labels"
        fi
        
        echo "扩展后的关键字: $KEYWORDS (任意一个匹配即可)"
        echo "扩展后的 Categories: $CATEGORIES (任意一个匹配即可)"
        echo "组合模式: 关键字匹配 AND Label匹配"
        echo "============================================"
    fi
    
    # 检查是否包含 "fix bug" 或 "fix-bug" 或 "fixbug" 或 "bugfix"
    if [[ "$categories_lower" == *"fix bug"* ]] || \
       [[ "$categories_lower" == *"fix-bug"* ]] || \
       [[ "$categories_lower" == *"fixbug"* ]] || \
       [[ "$categories_lower" == *"bugfix"* ]] || \
       [[ "$categories_lower" == *"bug fix"* ]]; then
        
        echo "============================================"
        echo "检测到 'fix bug' 预设，自动启用组合过滤模式"
        echo "============================================"
        
        USE_PRESET_MODE=true
        
        # 设置修复bug相关的关键字 (在 title 和 body 中搜索)
        local fix_bug_keywords="fix,fixed,fixes,fixing,resolve,resolved,resolves,patch,repair,correct,bug,issue,error,problem"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$fix_bug_keywords"
        else
            KEYWORDS="$KEYWORDS,$fix_bug_keywords"
        fi
        
        # 设置修复bug相关的 labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(fix[- ]?bug|bug[- ]?fix),?//gi' | sed 's/,$//' | sed 's/^,//')
        local fix_bug_labels="bug,bugfix,fix,hotfix,patch"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$fix_bug_labels"
        else
            CATEGORIES="$CATEGORIES,$fix_bug_labels"
        fi
        
        echo "扩展后的关键字: $KEYWORDS (任意一个匹配即可)"
        echo "扩展后的 Categories: $CATEGORIES (任意一个匹配即可)"
        echo "组合模式: 关键字匹配 AND Label匹配"
        echo "============================================"
    fi
    
    # 检查是否包含 "edge case & robustness" 或其变体
    if [[ "$categories_lower" == *"edge case"* ]] || \
       [[ "$categories_lower" == *"edge-case"* ]] || \
       [[ "$categories_lower" == *"edgecase"* ]] || \
       [[ "$categories_lower" == *"robustness"* ]] || \
       [[ "$categories_lower" == *"corner case"* ]] || \
       [[ "$categories_lower" == *"edge case & robustness"* ]] || \
       [[ "$categories_lower" == *"edge case and robustness"* ]]; then
        
        echo "============================================"
        echo "检测到 'edge case & robustness' 预设，自动启用组合过滤模式"
        echo "============================================"
        
        USE_PRESET_MODE=true
        
        # 设置边界情况/健壮性相关的关键字 (在 title 和 body 中搜索)
        local edge_case_keywords="edge case,corner case,boundary,edge,corner,overflow,underflow,null,empty,invalid,unexpected,exception,handle,handling,validation,validate,check,guard,defensive,robust,robustness,fallback,graceful,safety,safe"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$edge_case_keywords"
        else
            KEYWORDS="$KEYWORDS,$edge_case_keywords"
        fi
        
        # 设置边界情况/健壮性相关的 labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(edge[- ]?case[- &]*robustness|edge[- ]?case[- ]*and[- ]*robustness|edge[- ]?case|robustness|corner[- ]?case),?//gi' | sed 's/,$//' | sed 's/^,//')
        local edge_case_labels="edge-case,corner-case,robustness,validation,error-handling,bug,bugfix"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$edge_case_labels"
        else
            CATEGORIES="$CATEGORIES,$edge_case_labels"
        fi
        
        echo "扩展后的关键字: $KEYWORDS (任意一个匹配即可)"
        echo "扩展后的 Categories: $CATEGORIES (任意一个匹配即可)"
        echo "组合模式: 关键字匹配 AND Label匹配"
        echo "============================================"
    fi

    # 检查是否包含 "performance improvements" 或其变体
    if [[ "$categories_lower" == *"performance"* ]] || \
       [[ "$categories_lower" == *"optimization"* ]] || \
       [[ "$categories_lower" == *"improvement"* ]]; then
        
        echo "============================================"
        echo "检测到 'performance improvements' 预设，自动启用组合过滤模式"
        echo "============================================"
        
        USE_PRESET_MODE=true
        
        # 设置性能优化相关的关键字 (在 title 和 body 中搜索)
        local perf_keywords="performance,performant,optimize,optimization,optimized,efficient,efficiency,speed,fast,faster,slow,latency,throughput,memory,leak,resource,scalability,scale,bottleneck"
        if [[ -z "$KEYWORDS" ]]; then
            KEYWORDS="$perf_keywords"
        else
            KEYWORDS="$KEYWORDS,$perf_keywords"
        fi
        
        # 设置性能优化相关的 labels
        CATEGORIES=$(echo "$CATEGORIES" | sed -E 's/(performance|optimization|improvement|efficiency),?//gi' | sed 's/,$//' | sed 's/^,//')
        local perf_labels="performance,optimization,enhancement,speed,memory,efficiency"
        if [[ -z "$CATEGORIES" ]]; then
            CATEGORIES="$perf_labels"
        else
            CATEGORIES="$CATEGORIES,$perf_labels"
        fi
        
        echo "扩展后的关键字: $KEYWORDS (任意一个匹配即可)"
        echo "扩展后的 Categories: $CATEGORIES (任意一个匹配即可)"
        echo "组合模式: 关键字匹配 AND Label匹配"
        echo "============================================"
    fi
}

# 调用特殊预设处理
handle_special_presets

echo "============================================"
echo "过滤 JSONL 文件"
echo "============================================"
echo "输入目录: $INPUT_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "关键字: ${KEYWORDS:-无}"
echo "Categories: ${CATEGORIES:-无}"
echo "匹配模式: $MATCH_MODE"
echo "大小写敏感: $CASE_SENSITIVE"
echo "============================================"

# 构建 jq 过滤表达式
build_jq_filter() {
    local keyword_filter=""
    local category_filter=""
    
    # 确定关键字和 label 内部匹配模式
    # 预设模式：内部用 any，组合用 all
    # 普通模式：都用用户指定的 MATCH_MODE
    local internal_kw_mode="$MATCH_MODE"
    local internal_cat_mode="$MATCH_MODE"
    local combine_mode="$MATCH_MODE"
    
    if [[ "$USE_PRESET_MODE" == "true" ]]; then
        internal_kw_mode="any"   # 关键字之间用 or
        internal_cat_mode="any"  # label 之间用 or
        combine_mode="all"       # 关键字和label之间用 and
    fi
    
    # 构建关键字过滤条件
    if [[ -n "$KEYWORDS" ]]; then
        IFS=',' read -ra KW_ARRAY <<< "$KEYWORDS"
        local kw_conditions=()
        for kw in "${KW_ARRAY[@]}"; do
            # 去除首尾空格
            kw=$(echo "$kw" | xargs)
            if [[ "$CASE_SENSITIVE" == "false" ]]; then
                # 不区分大小写: 将字段和关键字都转为小写
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
    
    # 构建 category/label 过滤条件
    if [[ -n "$CATEGORIES" ]]; then
        IFS=',' read -ra CAT_ARRAY <<< "$CATEGORIES"
        local cat_conditions=()
        for cat in "${CAT_ARRAY[@]}"; do
            # 去除首尾空格
            cat=$(echo "$cat" | xargs)
            if [[ "$CASE_SENSITIVE" == "false" ]]; then
                cat_conditions+=("((.labels // []) | map(.name // \"\" | ascii_downcase) | any(. | contains(\"$(echo "$cat" | tr '[:upper:]' '[:lower:]')\")))")
            else
                cat_conditions+=("((.labels // []) | map(.name // \"\") | any(. | contains(\"$cat\")))")
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
    
    # 合并过滤条件
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

# 检查 jq 是否安装
if ! command -v jq &> /dev/null; then
    echo "Error: jq 未安装。请先安装 jq: brew install jq (macOS) 或 apt-get install jq (Linux)"
    exit 1
fi

# 构建过滤表达式
JQ_FILTER=$(build_jq_filter)
echo "JQ 过滤表达式: $JQ_FILTER"
echo "============================================"

# 统计
total_files=0
total_input_records=0
total_output_records=0

# 查找所有 *_raw_dataset.jsonl 文件
for jsonl_file in "$INPUT_DIR"/*_raw_dataset.jsonl; do
    if [[ ! -f "$jsonl_file" ]]; then
        echo "警告: 在 $INPUT_DIR 中没有找到 *_raw_dataset.jsonl 文件"
        break
    fi
    
    ((total_files++)) || true
    
    filename=$(basename "$jsonl_file")
    output_file="$OUTPUT_DIR/$filename"
    
    echo "处理: $filename"
    
    # 统计输入记录数
    input_count=$(wc -l < "$jsonl_file" | xargs)
    ((total_input_records += input_count)) || true
    
    # 逐行处理 (为了能够根据 patch size 过滤)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # 1. 首先尝试 JQ 过滤
        filtered_line=$(echo "$line" | jq -c "select($JQ_FILTER)")
        
        if [[ -n "$filtered_line" ]]; then
            # 2. 如果存在 MIN_PATCH_SIZE 限制，则计算 patch 大小
            if [[ "$MIN_PATCH_SIZE" -gt 0 ]]; then
                patch_content=$(echo "$filtered_line" | jq -r '.fix_patch // empty')
                if [[ -n "$patch_content" ]]; then
                    code_patch_size=$(calculate_code_patch_size "$patch_content")
                    if [[ "$code_patch_size" -gt "$MIN_PATCH_SIZE" ]]; then
                        echo "$filtered_line" >> "$output_file"
                    fi
                fi
            else
                # 没有 patch size 限制，直接写入
                echo "$filtered_line" >> "$output_file"
            fi
        fi
    done < "$jsonl_file"
    
    # 统计输出记录数
    if [[ -f "$output_file" ]]; then
        output_count=$(wc -l < "$output_file" | xargs)
    else
        output_count=0
    fi
    ((total_output_records += output_count)) || true
    
    echo "  输入: $input_count 条记录, 输出: $output_count 条记录"
    
    # 如果输出文件存在且为空,删除它
    if [[ -f "$output_file" && ! -s "$output_file" ]]; then
        rm "$output_file"
        echo "  (输出为空,已删除)"
    fi
done

echo "============================================"
echo "处理完成!"
echo "处理文件数: $total_files"
echo "总输入记录: $total_input_records"
echo "总输出记录: $total_output_records"
echo "输出目录: $OUTPUT_DIR"
echo "============================================"
