#!/usr/bin/env bash
set -euo pipefail

RAW_FILE="${1:?usage: $0 <file_raw_dataset.jsonl>}"

# 生成输出文件名：把 _raw_dataset.jsonl 改成 _extracted_ds.jsonl
OUT_FILE="${RAW_FILE%_raw_dataset.jsonl}_extracted_ds.jsonl"

# 清空输出
>"$OUT_FILE"

if command -v jq >/dev/null 2>&1; then
  jq -c 'select(has("issue_url") and .issue_url != null)
         | {org,repo,number,issue_url}' "$RAW_FILE" >>"$OUT_FILE"
else
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! printf '%s' "$line" | grep -q '"issue_url"'; then
      continue
    fi
    if printf '%s' "$line" | grep -q '"issue_url"[[:space:]]*:[[:space:]]*null'; then
      continue
    fi

    org=$(printf '%s' "$line" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    repo=$(printf '%s' "$line" | sed -n 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    number=$(printf '%s' "$line" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    issue_url=$(printf '%s' "$line" | sed -n 's/.*"issue_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    [ -n "$issue_url" ] || continue

    printf '{"org":"%s","repo":"%s","number":%s,"issue_url":"%s"}\n' \
      "$org" "$repo" "$number" "$issue_url" >>"$OUT_FILE"

  done < "$RAW_FILE"
fi

echo "Generated: $OUT_FILE"