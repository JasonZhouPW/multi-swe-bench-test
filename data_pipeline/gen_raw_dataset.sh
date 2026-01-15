#!/bin/bash
set -e  # 一旦有命令出错就退出

# 参数配置（可通过命令行参数覆盖）
# 默认值（如需更改，可使用 -o/-l/-s/-n/-t 参数）
# OUTPUT_DIR="data/raw_datasets/catchorg__Catch6"
LANGUAGE="Go"
MIN_STARS=100000
MAX_RESULTS=200
TOKEN="./tokens.txt"  # 默认 token 文件路径，或直接填写 token 字符串，如 "ghp_xxx"
PERCENTAGE=80.0
# 其他默认参数（通常无需修改）
MAX_WORKERS=50
DISTRIBUTE="round"
DELAY_ON_ERROR=600
RETRY_ATTEMPTS=8
# 默认使用当前日期（YYYY-MM-DD）作为 CREATED_AT，可通过脚本修改或导出环境变量覆盖
CREATED_AT="2025-01-01" # default value
TODAY="$(date '+%Y-%m-%d')"

KEY_WORDS="refactor"
OUTPUT_DIR="data/raw_datasets/${TODAY}/${KEY_WORDS}"


# Usage/help
usage() {
    echo "Usage: $0 [-o output_dir] [-l language] [-s min_stars] [-n max_results] [-t token] [-e exclude_repos]"
    echo "  -o output_dir    Output directory for raw datasets (default: $OUTPUT_DIR)"
    echo "  -l language      Language filter (default: $LANGUAGE)"
    echo "  -s min_stars     Minimum stars filter (default: $MIN_STARS)"
    echo "  -n max_results   Max repos to fetch (default: $MAX_RESULTS)"
    echo "  -t token         GitHub token (default: value in script)"
    echo "  -e exclude_repos  Comma-separated list of repos to exclude (format: org/repo)"
    echo "  -c created_at    Fetch PRs/Issues created on or after this date (default: $CREATED_AT)"
    exit 1
}

# Parse command-line options
while getopts ":o:l:s:n:t:e:c:h" opt; do
  case $opt in
    o) OUTPUT_DIR="$OPTARG" ;;
    l) LANGUAGE="$OPTARG" ;;
    s) MIN_STARS="$OPTARG" ;;
    n) MAX_RESULTS="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    e) EXCLUDE_REPOS="$OPTARG" ;;
    c) CREATED_AT="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
shift $((OPTIND -1))

# 显示当前配置
echo "Configuration:"
echo "  OUTPUT_DIR = $OUTPUT_DIR"
echo "  LANGUAGE   = $LANGUAGE"
echo "  MIN_STARS  = $MIN_STARS"
echo "  MAX_RESULTS= $MAX_RESULTS"
echo "  EXCLUDE_REPOS = ${EXCLUDE_REPOS:-<none>}"

# 如果未通过 -t 提供 token，尝试从常见环境变量读取
if [ "$TOKEN" = "xxxxx" ] || [ -z "$TOKEN" ]; then
    TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_API_TOKEN:-}}}"
    if [ -z "$TOKEN" ]; then
        echo "❌ Error: GitHub token not provided. Set with -t or export GITHUB_TOKEN/GH_TOKEN/GITHUB_API_TOKEN." >&2
        exit 1
    else
        echo "Using GitHub token from environment."
    fi
fi

# 如果 TOKEN 指向一个文件路径（如 ./tokens.txt），则读取文件中的非空行并转换为逗号分隔的字符串
if [ -f "$TOKEN" ]; then
    echo "TOKEN is a file path, reading tokens from: $TOKEN"
    # 读取非空行，去掉首尾空白，然后合并为以逗号分隔的字符串
    TOKENS_CSV=$(awk 'NF{gsub(/^[ \t]+|[ \t]+$/, ""); print}' "$TOKEN" | paste -sd, -)
    if [ -z "$TOKENS_CSV" ]; then
        echo "❌ Error: Token file $TOKEN is empty or contains only whitespace." >&2
        exit 1
    fi
    TOKEN="$TOKENS_CSV"
    # 可选：显示读取到的 token 个数（不打印具体 token 以免泄露）
    TOKEN_COUNT=$(echo "$TOKEN" | awk -F',' '{print NF}')
    echo "Read $TOKEN_COUNT tokens from file."
fi

# 找到合适的 Python 解释器（要求 Python >= 3.10）
PYTHON_CMD=""
for cmd in python python3 python3.11 python3.10; do
    if command -v $cmd >/dev/null 2>&1; then
        ver=$($cmd -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        maj=$(echo "$ver" | cut -d. -f1)
        min=$(echo "$ver" | cut -d. -f2)
        if [ "$maj" -gt 3 ] || { [ "$maj" -eq 3 ] && [ "$min" -ge 10 ]; }; then
            PYTHON_CMD=$cmd
            break
        fi
    fi
done
if [ -z "$PYTHON_CMD" ]; then
    echo "❌ Error: Python >= 3.10 is required. Activate your env (e.g., conda activate py311) or install Python 3.10+." >&2
    exit 1
fi

echo "Using interpreter: $PYTHON_CMD ($($PYTHON_CMD -V 2>&1))"

# 第一步：爬取 GitHub 仓库
echo "Step 1: Crawl GitHub repos..."
$PYTHON_CMD -m multi_swe_bench.collect.crawl_repos \
    --output_dir "$OUTPUT_DIR" \
    --language "$LANGUAGE" \
    --min_stars "$MIN_STARS" \
    --max_results "$MAX_RESULTS" \
    --token "$TOKEN"

# 找到刚生成的 CSV 文件
CSV_FILE=$(ls -t "$OUTPUT_DIR"/github_${LANGUAGE}_repos_*.csv | head -n 1)
echo "Generated CSV file: $CSV_FILE"

echo "Step 1.1: Filter repos..."
$PYTHON_CMD -m multi_swe_bench.collect.filter_repo \
    --input_file "$CSV_FILE" \
    --output_file "$OUTPUT_DIR/filtered_repos_$LANGUAGE.csv" \
    --tokens_file "./tokens.txt" \
    --min_total_pr_issues 200 \
    --min_forks 200 \
    --language "$LANGUAGE" \
    --min_lang_percent "$PERCENTAGE" \
    --max_workers 10 \
    --exclude_repos "$EXCLUDE_REPOS"
# 更新 CSV_FILE 为过滤后的文件
CSV_FILE="$OUTPUT_DIR/filtered_repos_$LANGUAGE.csv"
echo "Filtered CSV file: $CSV_FILE"

# 第二步：从仓库获取数据
echo "Step 2: Get data from repos..."
$PYTHON_CMD -m multi_swe_bench.collect.get_from_repos_pipeline \
    --csv_file "$CSV_FILE" \
    --out_dir "$OUTPUT_DIR" \
    --max_workers "$MAX_WORKERS" \
    --distribute "$DISTRIBUTE" \
    --delay-on-error "$DELAY_ON_ERROR" \
    --retry-attempts "$RETRY_ATTEMPTS" \
    --key_words "$KEY_WORDS" \
    --created_at "$CREATED_AT" \
    --token "$TOKEN" \
    --exclude-repos "$EXCLUDE_REPOS"

echo "All done!"

# move to copy_raw_dataset.sh
# 如果在out_dir下存在*_raw_dataset.jsonl文件并且文件size大于0，将其拷贝到上层的raw_datasets目录下
# RAW_DATASET_FILES=("$OUTPUT_DIR"/*_raw_dataset.jsonl)
# for file in "${RAW_DATASET_FILES[@]}"; do
#     if [ -f "$file" ] && [ -s "$file" ]; then
#         cp "$file" "data/raw_datasets/"
#         echo "Copied $file to data/raw_datasets/"
#     fi
# done