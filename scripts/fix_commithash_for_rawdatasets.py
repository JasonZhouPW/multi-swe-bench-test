#!/usr/bin/env python3
"""
修复raw_dataset jsonl文件中的base_commit_hash字段
直接从记录中读取org, repo, number，从GitHub API获取正确的commit hash
"""

import os
import json
import argparse
import time
import sys
from pathlib import Path
import requests

# GitHub API配置
GITHUB_API_BASE = "https://api.github.com"
HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}


def load_github_token(token_file="./tokens.txt"):
    """加载GitHub token (随机选择一个)"""
    try:
        import random
        with open(token_file, "r") as f:
            tokens = [line.strip() for line in f if line.strip()]
        if not tokens:
            print(f"No tokens found in {token_file}")
            return None
        return random.choice(tokens)
    except FileNotFoundError:
        print(f"Token file {token_file} not found")
        return None


def get_correct_commit_hash(org, repo, pr_number, token):
    """
    通过GitHub API获取PR的正确commit hash (第一个commit的parent)
    """
    repo_path = f"{org}/{repo}"
    url = f"{GITHUB_API_BASE}/repos/{repo_path}/pulls/{pr_number}/commits"

    headers = HEADERS.copy()
    if token:
        headers["Authorization"] = f"Bearer {token}"

    response = requests.get(url, headers=headers)

    # 处理速率限制
    if response.status_code == 429:
        reset_time = int(response.headers.get("X-RateLimit-Reset", time.time() + 60))
        sleep_time = max(reset_time - int(time.time()), 0) + 1
        print(f"Rate limited. Sleeping for {sleep_time} seconds...")
        time.sleep(sleep_time)
        return get_correct_commit_hash(org, repo, pr_number, token)  # 重试

    # 处理其他HTTP错误
    response.raise_for_status()

    commits = response.json()
    if not commits or len(commits) == 0:
        raise ValueError(f"No commits found for PR {pr_number}")
    
    parents = commits[0].get("parents", [])
    if not parents:
        raise ValueError(f"No parent commits found for PR {pr_number}")
    
    return parents[0]["sha"]


def process_jsonl_file(file_path, token):
    """
    处理单个jsonl文件，更新其中的base_commit_hash字段
    """
    print(f"Processing file: {file_path}")

    # 读取所有行
    lines = []
    modified_count = 0

    with open(file_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            if not line.strip():
                continue

            try:
                data = json.loads(line)

                # 直接从记录中读取org, repo, number
                org = data.get("org")
                repo = data.get("repo")
                pr_number = data.get("number")
                
                if not org or not repo or not pr_number:
                    print(f"Warning: Missing org/repo/number in line {line_num}")
                    lines.append(line)
                    continue

                record_id = f"{org}/{repo}#{pr_number}"

                # 获取当前的base_commit_hash值
                old_hash = data.get("base_commit_hash")
                
                # 检查base.sha是否存在
                # base_obj = data.get("base")
                # base_sha = base_obj.get("sha") if isinstance(base_obj, dict) else None

                try:
                    correct_hash = get_correct_commit_hash(org, repo, pr_number, token)

                    # 检查是否需要更新
                    needs_update = (old_hash != correct_hash) 

                    if needs_update:
                        # 更新base_commit_hash字段
                        print(f"Updating {record_id}: base_commit_hash {old_hash} -> {correct_hash}")
                        data["base_commit_hash"] = correct_hash
                        
                        # 同步更新base.sha
                        # if isinstance(base_obj, dict):
                        #     print(f"Updating {record_id}: base.sha {base_sha} -> {correct_hash}")
                        #     base_obj["sha"] = correct_hash
                        
                        modified_count += 1
                        print(f"Successfully updated {record_id}")

                        # 将更新后的数据写回
                        lines.append(json.dumps(data, ensure_ascii=False) + "\n")
                    else:
                        # 已经一致，保持原样
                        print(f"Skipping {record_id}: already correct ({correct_hash[:8]}...)")
                        lines.append(line)

                except Exception as e:
                    print(f"Error processing {record_id}: {e}")
                    lines.append(line)  # 保留原始行


            except json.JSONDecodeError as e:
                print(f"Error decoding JSON in line {line_num}: {e}")
                lines.append(line)  # 保留原始行

    # 写回文件
    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(lines)

    print(f"File {file_path}: {modified_count} records updated")
    return modified_count


def process_directory(directory, token):
    """
    遍历目录下所有jsonl文件并处理
    """
    directory = Path(directory)
    if not directory.exists():
        print(f"Directory {directory} does not exist")
        return

    jsonl_files = list(directory.glob("*.jsonl"))
    if not jsonl_files:
        print(f"No .jsonl files found in {directory}")
        return

    total_modified = 0
    for file_path in jsonl_files:
        try:
            modified_count = process_jsonl_file(file_path, token)
            total_modified += modified_count
        except Exception as e:
            print(f"Error processing file {file_path}: {e}")

    print(f"\nTotal: {total_modified} records updated across {len(jsonl_files)} files")


def main():
    parser = argparse.ArgumentParser(description="Fix base_commit_hash in raw_dataset jsonl files")
    parser.add_argument("directory", help="Directory containing jsonl files")
    parser.add_argument(
        "--token-file", default="./tokens.txt", help="Path to GitHub token file"
    )

    args = parser.parse_args()

    # 加载token
    token = load_github_token(args.token_file)
    if not token:
        print("Warning: No GitHub token found. Rate limits may apply.")

    # 处理目录
    process_directory(args.directory, token)


if __name__ == "__main__":
    main()
