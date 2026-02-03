#!/usr/bin/env python3
"""
修复jsonl文件中的base_commit_hash字段
根据instance_id从GitHub API获取正确的commit hash
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


def parse_instance_id(instance_id):
    """
    解析instance_id格式: owner__repo-pr_number
    例如: apache__skywalking-13677
    """
    if "-" not in instance_id:
        raise ValueError(f"Invalid instance_id format: {instance_id}")

    # 分离PR号和仓库信息
    repo_part, pr_number = instance_id.rsplit("-", 1)
    # 将双下划线替换为斜杠得到仓库路径
    repo_path = repo_part.replace("__", "/")

    return repo_path, pr_number



def get_correct_commit_hash(repo_path, pr_number, token):
    """
    通过GitHub API获取PR的正确commit hash
    """
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
        return get_correct_commit_hash(repo_path, pr_number, token)  # 重试

    # 处理其他HTTP错误
    response.raise_for_status()

    commits = response.json()
    return commits[0]["parents"][0]["sha"]


def process_jsonl_file(file_path, token):
    """
    处理单个jsonl文件，更新其中的base_commit字段
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

                # 获取instance_id
                instance_id = data.get("instance_id")
                if not instance_id:
                    print(f"Warning: No instance_id found in line {line_num}")
                    lines.append(line)
                    continue

                # 解析instance_id获取仓库和PR号
                try:
                    repo_path, pr_number = parse_instance_id(instance_id)
                except ValueError as e:
                    print(
                        f"Warning: Invalid instance_id format in line {line_num}: {e}"
                    )
                    lines.append(line)
                    continue

                # 获取当前的base_commit值
                old_hash = data.get("base_commit")
                
                # 只有当base_commit为null, None, 或空字符串时才获取正确的commit hash
                if old_hash is None or old_hash == "" or old_hash == "null":
                    try:
                        correct_hash = get_correct_commit_hash(repo_path, pr_number, token)

                        # 更新base_commit字段
                        print(f"Processing {instance_id}: {old_hash} -> {correct_hash}")
                        data["base_commit"] = correct_hash
                        modified_count += 1
                        print(f"Updated {instance_id}: {old_hash} -> {correct_hash}")

                        # 将更新后的数据写回
                        lines.append(json.dumps(data, ensure_ascii=False) + "\n")

                    except Exception as e:
                        print(f"Error processing {instance_id}: {e}")
                        lines.append(line)  # 保留原始行
                else:
                    # base_commit已有有效值，保持原样
                    print(f"Skipping {instance_id}: base_commit already has value '{old_hash}'")
                    lines.append(line)

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
    parser = argparse.ArgumentParser(description="Fix base_commit_hash in jsonl files")
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
