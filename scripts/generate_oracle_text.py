import argparse
import json
import os
import random
import requests
import time
import re
from pathlib import Path
from typing import List, Optional

GITHUB_API = "https://api.github.com"
HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}


def load_tokens(token_file="./tokens.txt"):
    """
    加载GitHub token列表
    """
    try:
        with open(token_file, "r") as f:
            tokens = [line.strip() for line in f if line.strip()]
        return tokens
    except FileNotFoundError:
        print(f"Token file {token_file} not found")
        return []


def get_random_token(tokens):
    """
    从token列表中随机选择一个
    """
    if not tokens:
        return None
    return random.choice(tokens)


def github_get(url: str, token: Optional[str] = None):
    """
    通过GitHub API获取数据
    """
    headers = HEADERS.copy()
    if token:
        headers["Authorization"] = f"Bearer {token}"

    response = requests.get(url, headers=headers)

    if response.status_code == 429:
        reset_time = int(response.headers.get("X-RateLimit-Reset", time.time() + 60))
        sleep_time = max(reset_time - int(time.time()), 0) + 1
        print(f"Rate limited. Sleeping for {sleep_time} seconds...")
        time.sleep(sleep_time)
        return github_get(url, token)

    response.raise_for_status()
    return response.json()


def clean_text(text: str) -> str:
    if not text:
        return ""

    # remove URLs
    text = re.sub(r"http[s]?://\S+", "", text)

    # remove markdown images
    text = re.sub(r"!\[.*?\]\(.*?\)", "", text)

    # collapse excessive newlines
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


def fetch_issue_from_pr(
    owner: str, repo: str, pr_number: int, token: Optional[str] = None
):
    pr = github_get(f"{GITHUB_API}/repos/{owner}/{repo}/pulls/{pr_number}", token)

    issue_number = pr["number"]
    issue = github_get(
        f"{GITHUB_API}/repos/{owner}/{repo}/issues/{issue_number}", token
    )

    return pr, issue


def fetch_maintainer_comments(
    owner: str, repo: str, issue_number: int, token: Optional[str] = None
) -> List[str]:
    comments = github_get(
        f"{GITHUB_API}/repos/{owner}/{repo}/issues/{issue_number}/comments", token
    )

    maintainer_comments = []
    for c in comments:
        if c["author_association"] in {"MEMBER", "OWNER", "COLLABORATOR"}:
            body = clean_text(c["body"])
            if body:
                maintainer_comments.append(body)

    return maintainer_comments


def build_oracle_text(
    title: str,
    body: str,
    pr_body: str = "",
    maintainer_comments: Optional[List[str]] = None,
):
    parts = []

    parts.append(
        "You are given a GitHub issue from an open-source repository.\n\n"
        "The issue describes a bug or incorrect behavior in the codebase.\n"
        "Your task is to modify the code so that the issue is resolved.\n"
    )

    parts.append(f"Issue Title:\n{title.strip()}\n")
    parts.append(f"Issue Description:\n{clean_text(body)}\n")

    additional_context = []

    if pr_body:
        additional_context.append(clean_text(pr_body))

    if maintainer_comments:
        additional_context.extend(maintainer_comments[:2])  # 控制 Oracle 信息量

    if additional_context:
        parts.append("Additional Context:\n" + "\n\n".join(additional_context))

    return "\n".join(parts).strip()


def parse_instance_id(instance_id):
    """
    解析instance_id格式: owner__repo-pr_number
    例如: apache__skywalking-13677
    """
    if "-" not in instance_id:
        raise ValueError(f"Invalid instance_id format: {instance_id}")

    repo_part, pr_number = instance_id.rsplit("-", 1)
    repo_path = repo_part.replace("__", "/")

    owner, repo = repo_path.split("/")
    return owner, repo, pr_number


def process_jsonl_file(file_path, token):
    """
    处理单个jsonl文件，更新其中的text字段
    """
    print(f"Processing file: {file_path}")

    lines = []
    updated_count = 0

    with open(file_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            if not line.strip():
                continue

            try:
                data = json.loads(line)

                # 如果text字段不为空，跳过
                if data.get("text") and data["text"].strip():
                    lines.append(line)
                    continue

                # 获取instance_id
                instance_id = data.get("instance_id")
                if not instance_id:
                    print(f"Warning: No instance_id found in line {line_num}")
                    lines.append(line)
                    continue

                # 解析instance_id
                try:
                    owner, repo, pr_number = parse_instance_id(instance_id)
                    pr_number = int(pr_number)
                except ValueError as e:
                    print(
                        f"Warning: Invalid instance_id format in line {line_num}: {e}"
                    )
                    lines.append(line)
                    continue

                # 获取PR和issue信息
                try:
                    pr, issue = fetch_issue_from_pr(owner, repo, pr_number, token)

                    # 获取maintainer comments
                    maintainer_comments = fetch_maintainer_comments(
                        owner, repo, issue["number"], token
                    )

                    # 构建oracle text
                    oracle_text = build_oracle_text(
                        title=issue["title"],
                        body=issue["body"] or "",
                        pr_body=pr.get("body") or "",
                        maintainer_comments=maintainer_comments,
                    )

                    # 更新text字段
                    data["text"] = oracle_text
                    updated_count += 1
                    print(f"Updated text for {instance_id}")

                    # 将更新后的数据写回
                    lines.append(json.dumps(data, ensure_ascii=False) + "\n")

                except Exception as e:
                    print(f"Error processing {instance_id}: {e}")
                    lines.append(line)  # 保留原始行

            except json.JSONDecodeError as e:
                print(f"Error decoding JSON in line {line_num}: {e}")
                lines.append(line)  # 保留原始行

    # 写回文件
    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(lines)

    print(f"File {file_path}: {updated_count} records updated")
    return updated_count


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

    total_updated = 0
    for file_path in jsonl_files:
        try:
            updated_count = process_jsonl_file(file_path, token)
            total_updated += updated_count
        except Exception as e:
            print(f"Error processing file {file_path}: {e}")

    print(f"\nTotal: {total_updated} records updated across {len(jsonl_files)} files")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--directory", type=str, help="Directory containing jsonl files"
    )
    parser.add_argument(
        "--token-file", default="./tokens.txt", help="Path to GitHub token file"
    )
    parser.add_argument("--owner", type=str, help="Repository owner")
    parser.add_argument("--repo", type=str, help="Repository name")
    parser.add_argument("--pr", type=int, help="Pull request number")

    args = parser.parse_args()

    # 加载tokens
    tokens = load_tokens(args.token_file)
    if not tokens:
        print("Warning: No GitHub token found. Rate limits may apply.")
        token = None
    else:
        token = get_random_token(tokens)

    # 如果提供了directory参数，则处理整个目录
    if args.directory:
        process_directory(args.directory, token)
        return

    # 否则，使用原有的单个PR处理逻辑
    if not args.owner or not args.repo or not args.pr:
        print("Error: Either --directory or (--owner --repo --pr) is required")
        return

    pr, issue = fetch_issue_from_pr(args.owner, args.repo, args.pr, token)

    maintainer_comments = fetch_maintainer_comments(
        args.owner, args.repo, issue["number"], token
    )

    oracle_text = build_oracle_text(
        title=issue["title"],
        body=issue["body"] or "",
        pr_body=pr.get("body") or "",
        maintainer_comments=maintainer_comments,
    )

    print(oracle_text)


if __name__ == "__main__":
    main()
