#!/bin/bash
set -e  # 一旦有命令出错就退出

# 参数配置
OUTPUT_DIR="data/raw_datasets/catchorg__Catch6"
#LANGUAGE="C++"
#LANGUAGE="Python"
#LANGUAGE="Java"
#LANGUAGE="JavaScript"
#LANGUAGE="C"
#LANGUAGE="TypeScript"
#LANGUAGE="Ruby"
LANGUAGE="Go"
MIN_STARS=1000
MAX_RESULTS=1
TOKEN="xxxxx"
MAX_WORKERS=50
DISTRIBUTE="round"
DELAY_ON_ERROR=600
RETRY_ATTEMPTS=8
CREATED_AT="2024-11-28"
KEY_WORDS="refactor"

# 第一步：爬取 GitHub 仓库
echo "Step 1: Crawl GitHub repos..."
python3 -m multi_swe_bench.collect.crawl_repos \
    --output_dir "$OUTPUT_DIR" \
    --language "$LANGUAGE" \
    --min_stars "$MIN_STARS" \
    --max_results "$MAX_RESULTS" \
    --token "$TOKEN"

# 找到刚生成的 CSV 文件
CSV_FILE=$(ls -t "$OUTPUT_DIR"/github_${LANGUAGE}_repos_*.csv | head -n 1)
echo "Generated CSV file: $CSV_FILE"

# 第二步：从仓库获取数据
echo "Step 2: Get data from repos..."
python3 -m multi_swe_bench.collect.get_from_repos_pipeline \
    --csv_file "$CSV_FILE" \
    --out_dir "$OUTPUT_DIR" \
    --max_workers "$MAX_WORKERS" \
    --distribute "$DISTRIBUTE" \
    --delay-on-error "$DELAY_ON_ERROR" \
    --retry-attempts "$RETRY_ATTEMPTS" \
    --key_words "$KEY_WORDS" \
    --created_at "$CREATED_AT" \
    --token "$TOKEN"

echo "All done!"