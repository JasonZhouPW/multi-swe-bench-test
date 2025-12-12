#!/bin/bash

# 确保输入参数
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <org> <repo> <instance_id> <language>"
  exit 1
fi

# 获取输入参数
ORG=$1
REPO=$2
INSTANCE_ID=$3
LANGUAGE=$4

# GitHub API URL
API_URL="https://api.github.com/repos/$ORG/$REPO/branches/main"

# 使用 curl 获取 main 分支的最新 commit hash
COMMIT_HASH=$(curl -s "$API_URL" | jq -r .commit.sha)

# 如果没有找到 commit hash，则输出错误信息并退出
if [ "$COMMIT_HASH" == "null" ]; then
  echo "Error: Unable to fetch commit hash. Please check the repository and branch."
  exit 1
fi

# 获取当前时间
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 创建 dataset.jsonl 文件并写入
echo "{\"repo\":\"$ORG/$REPO\",\"instance_id\":\"$INSTANCE_ID\",\"base_commit\":\"$COMMIT_HASH\",\"create_at\":\"$CURRENT_TIME\",\"language\":\"$LANGUAGE\"}" > dataset.jsonl

# 输出生成的 jsonl 文件内容
cat dataset.jsonl
