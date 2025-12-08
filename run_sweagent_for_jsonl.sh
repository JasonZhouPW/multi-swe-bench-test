#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="${1:?usage: $0 <work-dir> [jsonl_path]}"
JSONL="${2:-$WORK_DIR/extracted_ds.jsonl}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="$SCRIPT_DIR/ollama_cfg.yaml"
GITHUB_DIR="$WORK_DIR/github"

mkdir -p "$GITHUB_DIR"

if command -v jq >/dev/null 2>&1; then
  jq -r 'select(has("org") and has("repo") and has("issue_url") and .issue_url != null) | [.org,.repo,.issue_url] | @tsv' "$JSONL" |
  while IFS=$'\t' read -r org repo issue_url; do
    [ -n "$org" ] && [ -n "$repo" ] && [ -n "$issue_url" ] || continue
    clone_dir="$GITHUB_DIR/$org/$repo"
    if [ -d "$clone_dir/.git" ]; then
      :
    else
      mkdir -p "$(dirname "$clone_dir")"
      git clone "https://github.com/$org/$repo.git" "$clone_dir"
    fi
    sweagent run --config "$CFG" \
      --env.repo.path="$clone_dir" \
      --problem_statement.github_url="$issue_url" \
      --env.deployment.image="python:3.11"
  done
else
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$line" | grep -q '"issue_url"' || continue
    printf '%s' "$line" | grep -q '"issue_url"[[:space:]]*:[[:space:]]*null' && continue
    org=$(printf '%s' "$line" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    repo=$(printf '%s' "$line" | sed -n 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    issue_url=$(printf '%s' "$line" | sed -n 's/.*"issue_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$org" ] && [ -n "$repo" ] && [ -n "$issue_url" ] || continue
    clone_dir="$GITHUB_DIR/$org/$repo"
    if [ -d "$clone_dir/.git" ]; then
      :
    else
      mkdir -p "$(dirname "$clone_dir")"
      git clone "https://github.com/$org/$repo.git" "$clone_dir"
    fi
    sweagent run --config "$CFG" \
      --env.repo.path="$clone_dir" \
      --problem_statement.github_url="$issue_url" \
      --env.deployment.image="python:3.11"
  done < "$JSONL"
fi

