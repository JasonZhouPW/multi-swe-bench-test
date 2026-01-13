#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="${1:?usage: $0 <work-dir> [jsonl_path]}"
JSONL="${2:-$WORK_DIR/extracted_ds.jsonl}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="./configs/sweagent.yaml"
GITHUB_DIR="$WORK_DIR/github"
PATCH_DIR="$WORK_DIR/patches"

mkdir -p "$GITHUB_DIR" "$PATCH_DIR"
echo "config file:$CFG"
if command -v jq >/dev/null 2>&1; then
  jq -r 'select(has("org") and has("repo") and has("number") and has("issue_url") and .issue_url != null) | [.org,.repo,.number,.issue_url] | @tsv' "$JSONL" |
  while IFS=$'\t' read -r org repo number issue_url; do
    echo "$org $repo $issue_url"
    [ -n "$org" ] && [ -n "$repo" ] && [ -n "$issue_url" ] || continue
    if [[ "$issue_url" =~ ^https://api.github.com/repos/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
      issueNumber="${BASH_REMATCH[3]}"
      issue_url="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/issues/${BASH_REMATCH[3]}"
    fi
    clone_dir="$GITHUB_DIR/$org/$repo"
    if [ -d "$clone_dir/.git" ]; then
      :
    else
      mkdir -p "$(dirname "$clone_dir")"
      git clone "https://github.com/$org/$repo.git" "$clone_dir"
    fi
    log_file="$(mktemp)"
    echo "log file:$log_file"
    set +e
    echo "Running command:$CFG,$clone_dir,  $org/$repo, $issue_url"
    sweagent run --config "$CFG" \
      --env.repo.path="$clone_dir" \
      --problem_statement.github_url="$issue_url" \
      --env.deployment.image="python:3.11" | tee "$log_file"
    status=$?
    set -e
    if grep -q "Submission successful" "$log_file"; then
      patch_path=$(awk '/PATCH_FILE_PATH=/{printf $0; getline; print $0}' "$log_file" | awk -F"'" '{print $2}' | tr -d ' ')
      if [ -n "$patch_path" ] && [ -f "$patch_path" ]; then
        echo "cp $patch_path $PATCH_DIR/${org}_${repo}_${number}_${issueNumber}.patch"
        cp "$patch_path" "$PATCH_DIR/${org}_${repo}_${number}_${issueNumber}.patch"
      fi
    fi
    rm -f "$log_file"
  done
else
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$line" | grep -q '"issue_url"' || continue
    printf '%s' "$line" | grep -q '"issue_url"[[:space:]]*:[[:space:]]*null' && continue
    org=$(printf '%s' "$line" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    repo=$(printf '%s' "$line" | sed -n 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    # number=$(printf '%s' "$line" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    number=$(printf '%s' "$line" | sed -n 's/.*"number":[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    issue_url=$(printf '%s' "$line" | sed -n 's/.*"issue_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "line:$line"
    echo "number:$number"
    [ -n "$org" ] && [ -n "$repo" ] && [ -n "$number" ] && [ -n "$issue_url" ] || continue
    if [[ "$issue_url" =~ ^https://api.github.com/repos/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
      issueNumber="${BASH_REMATCH[3]}"
      issue_url="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/issues/${BASH_REMATCH[3]}"
    fi
    clone_dir="$GITHUB_DIR/$org/$repo"
    if [ -d "$clone_dir/.git" ]; then
      :
    else
      mkdir -p "$(dirname "$clone_dir")"
      git clone "https://github.com/$org/$repo.git" "$clone_dir"
    fi
    log_file="$(mktemp)"
    echo "log file:$log_file"
    set +e
    echo "Running command:$CFG,$clone_dir,  $org/$repo,$number, $issue_url"

    sweagent run --config "$CFG" \
      --env.repo.path="$clone_dir" \
      --problem_statement.github_url="$issue_url" \
      --env.deployment.image="python:3.11" | tee "$log_file"
    status=$?
    set -e
    echo "status:$status"
    if grep -q "Submission successful" "$log_file"; then
      echo "===Submission successful"
      # patch_path=$(grep -Eo "PATCH_FILE_PATH=['\"][^'\"]*\.patch['\"]" "$log_file" | tail -n100 | sed -E "s/^PATCH_FILE_PATH=['\"]//; s/['\"]$//")
      patch_path=$(awk '/PATCH_FILE_PATH=/{printf $0; getline; print $0}' "$log_file" | awk -F"'" '{print $2}' | tr -d ' ')
      echo "===patch_path:$patch_path"
      echo "===number:$number"
      if [ -n "$patch_path" ] && [ -f "$patch_path" ]; then
        # mkdir -p patches
        echo "cp $patch_path $PATCH_DIR/${org}_${repo}_${number}_${issueNumber}.patch"
        cp "$patch_path" "$PATCH_DIR/${org}_${repo}_${number}_${issueNumber}.patch"
      fi
    fi
    rm -f "$log_file"
  done < "$JSONL"
fi
