#!/bin/bash
set -e  # 一旦有命令出错就退出

# 参数配置（可通过命令行参数覆盖）
# 默认值（如需更改，可使用 -o/-l/-s/-n/-t 参数）
# OUTPUT_DIR="data/raw_datasets/catchorg__Catch6"
LANGUAGE="Go"
# MIN_STARS=100000
# MAX_RESULTS=2
TOKEN="./tokens.txt"  # 默认 token 文件路径，或直接填写 token 字符串，如 "ghp_xxx"
# PERCENTAGE=70.0
# 其他默认参数（通常无需修改）
MAX_WORKERS=50
DISTRIBUTE="round"
DELAY_ON_ERROR=600
RETRY_ATTEMPTS=8
# 默认使用当前日期（YYYY-MM-DD）作为 CREATED_AT，可通过脚本修改或导出环境变量覆盖
CREATED_AT="2025-01-01" # default value
TODAY="$(date '+%Y-%m-%d')"

KEY_WORDS=""
OUTPUT_DIR="data/raw_datasets/${TODAY}_${LANGUAGE}"


# Usage/help
usage() {
    echo "Usage: $0 [-o output_dir] [-t token] [-r org/repo]"
    echo "  -o output_dir   Output directory for raw datasets (default: $OUTPUT_DIR)"
    echo "  -l language     Language filter (default: $LANGUAGE)"
    echo "  -t token        GitHub token (default: value in script)"
    echo "  -r org/repo     Comma-separated list of specific repos to process (format: org/repo)"
    exit 1
}

# Parse command-line options
while getopts ":o:l:s:n:t:r:h" opt; do
  case $opt in
    o) OUTPUT_DIR="$OPTARG" ;;
    l) LANGUAGE="$OPTARG" ;;
    # s) MIN_STARS="$OPTARG" ;;
    # n) MAX_RESULTS="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    r) REPOS="$OPTARG" ;;
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
# echo "  MIN_STARS  = $MIN_STARS"
# echo "  MAX_RESULTS= $MAX_RESULTS"
echo "  REPOS = ${REPOS:-<none>}"

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
# splidt REPOS into array ,write to csv file $OUTPUT_DIR/filtered_repos.csv
if [ -n "${REPOS:-}" ]; then
    echo "Processing specific repos: $REPOS"
    IFS=',' read -r -a REPO_ARRAY <<< "$REPOS"
    mkdir -p "$OUTPUT_DIR"
    FILTERED_CSV="$OUTPUT_DIR/filtered_repos.csv"
    echo "Rank,Name,Stars,Forks,Description,URL,Last Updated" > "$FILTERED_CSV"
    RANK=1
    for repo in "${REPO_ARRAY[@]}"; do
        ORG_NAME=$(echo "$repo" | cut -d'/' -f1)
        REPO_NAME=$(echo "$repo" | cut -d'/' -f2)
        Stars=0
        Forks=0
        DESCRIPTION=""
        URL="https://api.github.com/repos/$ORG_NAME/$REPO_NAME"
        LAST_UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "$RANK,$ORG_NAME/$REPO_NAME,$Stars,$Forks,\"${DESCRIPTION}\",$URL,$LAST_UPDATED" >> "$FILTERED_CSV"
        RANK=$((RANK + 1))
    done
    CSV_FILE="$FILTERED_CSV"
else
    echo "Crawling repos for language: $LANGUAGE"
fi

echo "Filtered CSV file: $CSV_FILE"

# 第二步：从仓库获取数据
# echo "Step 2: Get data from repos..."
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
    # --exclude-repos "$EXCLUDE_REPOS"

echo "All done!"
