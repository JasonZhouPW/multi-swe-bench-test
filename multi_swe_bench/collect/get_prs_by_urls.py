import argparse
import json
import os
import re
import random
from pathlib import Path
from typing import List, Dict, Tuple
from github import Auth, Github
from multi_swe_bench.collect.util import get_tokens

def parse_pr_url(url: str) -> Tuple[str, str, int]:
    # Match https://github.com/org/repo/pull/number
    match = re.search(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)", url)
    if not match:
        raise ValueError(f"Invalid PR URL: {url}")
    return match.group(1), match.group(2), int(match.group(3))

def get_github(token: str) -> Github:
    auth = Auth.Token(token)
    return Github(auth=auth, per_page=100)

def fetch_pr_details(g: Github, org: str, repo_name: str, pr_number: int) -> dict:
    repo = g.get_repo(f"{org}/{repo_name}")
    pull = repo.get_pull(pr_number)
    
    def datetime_serializer(obj):
        from datetime import datetime
        if isinstance(obj, datetime):
            return obj.isoformat()
        return obj

    return {
        "org": org,
        "repo": repo_name,
        "number": pull.number,
        "state": pull.state,
        "title": pull.title,
        "body": pull.body,
        "url": pull.url,
        "id": pull.id,
        "node_id": pull.node_id,
        "html_url": pull.html_url,
        "diff_url": pull.diff_url,
        "patch_url": pull.patch_url,
        "issue_url": pull.issue_url,
        "created_at": datetime_serializer(pull.created_at),
        "updated_at": datetime_serializer(pull.updated_at),
        "closed_at": datetime_serializer(pull.closed_at),
        "merged_at": datetime_serializer(pull.merged_at),
        "merge_commit_sha": pull.merge_commit_sha,
        "labels": [label.name for label in pull.labels],
        "draft": pull.draft,
        "commits_url": pull.commits_url,
        "review_comments_url": pull.review_comments_url,
        "review_comment_url": pull.review_comment_url,
        "comments_url": pull.comments_url,
        "base": pull.base.raw_data,
        "commits": [c.raw_data for c in pull.get_commits()]
    }

def main():
    parser = argparse.ArgumentParser(description="Fetch PR details by URLs and save to JSONL per repo")
    parser.add_argument("--urls_file", required=True, help="File containing PR URLs")
    parser.add_argument("--out_dir", required=True, type=Path, help="Output directory")
    parser.add_argument("--tokens", nargs="*", help="API token(s) or path to token file")
    args = parser.parse_args()

    tokens = get_tokens(args.tokens)
    if not tokens:
        print("Error: No GitHub tokens provided.")
        return

    os.makedirs(args.out_dir, exist_ok=True)

    # 1. Parse URLs and group by repo
    repo_prs: Dict[str, List[int]] = {}
    with open(args.urls_file, "r") as f:
        for line in f:
            url = line.strip()
            if not url: continue
            try:
                org, repo, num = parse_pr_url(url)
                repo_key = f"{org}__{repo}"
                if repo_key not in repo_prs:
                    repo_prs[repo_key] = []
                repo_prs[repo_key].append(num)
            except ValueError as e:
                print(f"Skipping: {e}")

    # 2. Fetch and write
    for repo_key, pr_nums in repo_prs.items():
        org, repo_name = repo_key.split("__")
        out_file = args.out_dir / f"{repo_key}_prs.jsonl"
        print(f"Processing {org}/{repo_name} ({len(pr_nums)} PRs) -> {out_file.name}")
        
        # Use a random token for each repo to spread load
        g = get_github(random.choice(tokens))
        
        with open(out_file, "w", encoding="utf-8") as f:
            for num in pr_nums:
                print(f"  Fetching #{num}...")
                try:
                    pr_data = fetch_pr_details(g, org, repo_name, num)
                    f.write(json.dumps(pr_data, ensure_ascii=False) + "\n")
                except Exception as e:
                    print(f"  Failed to fetch #{num}: {e}")

    print("Done!")

if __name__ == "__main__":
    main()
