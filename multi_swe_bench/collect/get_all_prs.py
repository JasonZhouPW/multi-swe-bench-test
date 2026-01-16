# Copyright (c) 2024 Bytedance Ltd. and/or its affiliates

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

import argparse
import json
import random
import re
import requests
from datetime import datetime,timezone
from pathlib import Path

# from github import Auth, Github
from tqdm import tqdm

from multi_swe_bench.collect.util import get_tokens


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="A command-line tool for processing repositories."
    )
    parser.add_argument(
        "--out_dir", type=Path, required=True, help="Output directory path."
    )
    parser.add_argument(
        "--tokens",
        type=str,
        nargs="*",
        default=None,
        help="API token(s) or path to token file.",
    )
    parser.add_argument("--org", type=str, required=False, help="Organization name.")
    parser.add_argument("--repo", type=str, required=False, help="Repository name.")
    parser.add_argument("--created_at", type=str, required=False, default=None, help="Filter PRs created after this datetime (ISO format).")
    parser.add_argument("--merged_after", type=str, required=False, default=None, help="Filter PRs merged after this datetime (ISO format).")
    parser.add_argument("--key_words", type=str, required=False, default=None, help="keywords to filter PRs, separated by commas.")
    return parser


# def get_github(token) -> Github:
#     auth = Auth.Token(token)
#     return Github(auth=auth, per_page=100)

def is_relevant_pull(pull, key_words: str = None) -> bool:
    """
    判断 PR 是否可能是修复 issue 的 PR。
    """

    title = pull.title.lower() if pull.title else ""
    labels = [label.name.lower() for label in pull.labels]

    # rule 1: title: fix #123
    if re.search(r"fix\s*#\d+", title, re.IGNORECASE):
        return True

    # 默认关键词
    default_keywords = {"refactor"}

    # 用户指定 key_words（允许多个关键词用逗号分隔）
    if key_words is not None and key_words != "":
        user_keywords = {w.strip().lower() for w in key_words.split(",")}
        keywords = user_keywords
    else:
        keywords = default_keywords

    # print(f"=== Using keywords for filtering: {keywords}")
    # rule 2: labels contain keywords
    # if any(k in label for label in labels for k in keywords):
    #     return True
    if any(k in label for label in labels for k in keywords):
        return True
    if any(k in title for k in keywords):
        return True
    if pull.body and any(k in pull.body.lower() for k in keywords):
        return True

    return False

def main(tokens: list[str], out_dir: Path, org: str, repo: str, created_at: str = None, key_words: str = None, merged_after: str = None):
    print("starting get all pull requests")
    print(f"Output directory: {out_dir}")
    print(f"Tokens: {tokens}")
    print(f"Org: {org}")
    print(f"Repo: {repo}")
    print(f"Created At: {created_at}")
    print(f"Merged After: {merged_after}")
    print(f"Key Words: {key_words}")

    # Convert created_at string -> timezone-aware datetime
    filter_dt = None
    if created_at:
        try:
        # 支持 GitHub 风格：xxxx-xx-xxTxx:xx:xxZ
            created_at_clean = created_at.replace("Z", "+00:00")
            dt = datetime.fromisoformat(created_at_clean)
        except ValueError:
            raise ValueError(f"Invalid created_at format: {created_at}")
        # 如果用户输入的是没有时区的日期，补成 UTC
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        filter_dt = dt

    # Convert merged_after string -> timezone-aware datetime
    merged_dt = None
    if merged_after:
        try:
            merged_after_clean = merged_after.replace("Z", "+00:00")
            md = datetime.fromisoformat(merged_after_clean)
        except ValueError:
            raise ValueError(f"Invalid merged_after format: {merged_after}")
        if md.tzinfo is None:
            md = md.replace(tzinfo=timezone.utc)
        merged_dt = md

    print("token:", tokens)    
    tk = random.choice(tokens)
    print("Using token:", tk)
    # g = get_github(tk)
    print("org and repo:", org, repo)
    # r = g.get_repo(f"{org}/{repo}")
    print(f"Repository {org}/{repo} found.")
    def datetime_serializer(obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return obj

    with open(out_dir / f"{org}__{repo}_prs.jsonl", "w", encoding="utf-8") as file:
        # Use the Search API to fetch merged PRs with optional merged date filter
        headers = {"Accept": "application/vnd.github.v3+json", "Authorization": f"{tk}"}
        # print(f"headers:{headers}")
        # query = f"repo:{org}/{repo} is:pr is:merged"
        base_query_parts = [f"repo:{org}/{repo}", "is:pr", "is:merged"]

        if merged_after:
            base_query_parts.append(f" merged:>={merged_after}")
            # query += f" merged:>={merged_after}"
        if key_words is not None and key_words != "":
            for kw in key_words.split(","):
                kw_clean = kw.strip()
                if kw_clean:
                    base_query_parts.append(f'"{kw_clean}"')
        query = " ".join(base_query_parts)            
        # You can also include created_at in the query if desired, but we'll keep created_at as a secondary filter
        base_url = f"https://api.github.com/search/issues?q={query}&sort=updated&order=desc&per_page=100"

        url = base_url
        fetched = 0
        while url:
            resp = requests.get(url, headers=headers)
            # resp = requests.get(url)
            print(f"resp:{resp}")

            resp.raise_for_status()
            data = resp.json()
            items = data.get("items", [])

            for item in items:
                pr_number = item["number"]
                try:
                    pr_query_parts = [f"repo:{org}/{repo}", "is:pr", f"pr_number"]
                    query = " ".join(base_query_parts) 
                    pr_url = f"https://api.github.com/search/issues?q={query}"
                    prresp = requests.get(pr_url)
                    prdata = resp.json()
                    pritems = data.get("pritems", [])

                    # pull = r.get_pull(pr_number)
                except Exception as e:
                    print(f"Failed to fetch PR #{pr_number} details: {e}")
                    continue

                # Ensure merged
                # if not pull.is_merged():
                #     print(f"Skipping PR #{pull.number} not merged")
                #     continue

                # created_at filter (existing behavior)
                # if filter_dt is not None and filter_dt != "" and pull.created_at <= filter_dt:
                #     print(f"Skipping PR #{pull.number} created at {pull.created_at} ,required after {filter_dt}")
                #     continue

                # merged_at filter (if provided)
                # if merged_dt is not None:
                #     if pull.merged_at is None or pull.merged_at <= merged_dt:
                #         print(f"Skipping PR #{pull.number} merged at {pull.merged_at} ,required after {merged_dt}")
                #         continue

                # keyword filtering (existing behavior)
                # if key_words is not None and key_words != "" and not is_relevant_pull(pull, key_words):
                #     print(f"Skipping PR #{pull.number} not matching keywords")
                #     continue

                # print(f"Get PR #{pull.number} created at {pull.created_at} merged at {pull.merged_at} keywords {key_words} matched")
                file.write(
                    json.dumps(
                        {
                            "org": org,
                            "repo": repo,
                            "number": pritem["number"],
                            "state": pritem["state"],
                            "title": pritem["title"],
                            "body": pritem["body"],
                            "url": pritem["url"],
                            "id": pritem["id"],
                            "node_id": pritem["node_id"],
                            "html_url": pritem["html_url"],
                            "diff_url": pritem["diff_url"],
                            "patch_url": pritem["patch_url"],
                            "issue_url": pritem["issue_url"],
                            "created_at": pritem["created_at"],
                            "updated_at": pritem["updated_at"],
                            "closed_at": pritem["closed_at"],
                            "merged_at":pritem["merged_at"],
                            "merge_commit_sha": pritem["merge_commit_sha"],
                            "labels": [label["name"] for label in pull["labels"]],
                            "draft": pritem["draft"],
                            "commits_url": pritem["commits_url"],
                            "review_comments_url": pritem["review_comments_url"],
                            "review_comment_url": pritem["review_comment_url"],
                            "comments_url": pritem["comments_url"],
                            "base": pritem["base"]["raw_data"],
                            #  "org": org,
                            # "repo": repo,
                            # "number": pull.number,
                            # "state": pull.state,
                            # "title": pull.title,
                            # "body": pull.body,
                            # "url": pull.url,
                            # "id": pull.id,
                            # "node_id": pull.node_id,
                            # "html_url": pull.html_url,
                            # "diff_url": pull.diff_url,
                            # "patch_url": pull.patch_url,
                            # "issue_url": pull.issue_url,
                            # "created_at": datetime_serializer(pull.created_at),
                            # "updated_at": datetime_serializer(pull.updated_at),
                            # "closed_at": datetime_serializer(pull.closed_at),
                            # "merged_at": datetime_serializer(pull.merged_at),
                            # "merge_commit_sha": pull.merge_commit_sha,
                            # "labels": [label.name for label in pull.labels],
                            # "draft": pull.draft,
                            # "commits_url": pull.commits_url,
                            # "review_comments_url": pull.review_comments_url,
                            # "review_comment_url": pull.review_comment_url,
                            # "comments_url": pull.comments_url,
                            # "base": pull.base.raw_data,
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                fetched += 1

            # Pagination
            if "next" in resp.links:
                url = resp.links["next"]["url"]
            else:
                url = None

        print(f"Fetched {fetched} merged PRs from search.")


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)

    main(tokens, Path.cwd() / args.out_dir, args.org, args.repo, args.created_at, args.key_words, args.merged_after)
