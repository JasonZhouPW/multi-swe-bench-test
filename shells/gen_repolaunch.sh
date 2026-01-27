#!/bin/bash

# 确保输入参数
# if [ "$#" -ne 4 ]; then
#   echo "Usage: $0 <org> <repo> <instance_id> <language>"
#   exit 1
# fi

# 获取输入参数
ORG=$1
REPO=$2
INSTANCE_ID=$3
LANGUAGE=$4
COMMIT_HASH="${5:-}"

# GitHub API URL
if [ -n "$COMMIT_HASH" ]; then
  echo "Using provided commit hash: $COMMIT_HASH"
else
  echo "No commit hash provided, fetching from GitHub API..."
  API_URL="https://api.github.com/repos/$ORG/$REPO/branches/main"
  echo "Fetching commit hash from: $API_URL"
  # 使用 curl 获取 main 分支的最新 commit hash
  COMMIT_HASH=$(curl -s "$API_URL" | jq -r .commit.sha)

  # 如果没有找到 commit hash，则输出错误信息并退出
  if [ "$COMMIT_HASH" == "null" ]; then
    echo "Error: Unable to fetch commit hash. Please check the repository and branch."
    API_URL="https://api.github.com/repos/$ORG/$REPO/branches/master"
    echo "Fetching commit hash from: $API_URL"
    COMMIT_HASH=$(curl -s "$API_URL" | jq -r .commit.sha)
    if [ "$COMMIT_HASH" == "null" ]; then
        echo "Error: Unable to fetch commit hash from both main and master branches. Please check the repository."
        exit 1
    fi  
  fi
fi




# 获取当前时间
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 创建 dataset.jsonl 文件并写入
echo "{\"repo\":\"$ORG/$REPO\",\"instance_id\":\"$INSTANCE_ID\",\"base_commit\":\"$COMMIT_HASH\",\"create_at\":\"$CURRENT_TIME\",\"language\":\"$LANGUAGE\"}" > dataset.jsonl

# 输出生成的 jsonl 文件内容
cat dataset.jsonl

# check repolaunch folder exists
if [ ! -d "repolaunch" ]; then
  mkdir -p "repolaunch"
fi
cp dataset.jsonl repolaunch/dataset.jsonl
cp configs/repolauch.json repolaunch/repolaunch.json
cd repolaunch
# check RepoLaunch exists
if [ ! -f "RepoLaunch" ]; then
  echo "Cloning RepoLaunch..."
  git clone https://github.com/microsoft/RepoLaunch.git
  cp configs/repolauch.json RepoLaunch/configs/repolauch.json
fi
cd RepoLaunch
python -m pip install -e .

# 运行 repolaunch
echo "Running RepoLaunch..."
echo "set environment variable..."
# check if OPENAI_API_KEY and OPENAI_BASE_URL are set

export OPENAI_BASE_URL=https://open.bigmodel.cn/api/paas/v4 #defaut for Alibaba replace with your own openai base url
export OPENAI_API_KEY=6fd15cb77cff4a31b151cdd87be8dac9.QESK5aHeMk4TJShD
export TAVILY_API_KEY=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

python -m launch.run --config-path ../repolaunch.json
