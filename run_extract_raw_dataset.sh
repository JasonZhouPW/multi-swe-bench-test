#!/usr/bin/env bash
set -euo pipefail

DIR="${1:-.}"
OUT="${2:-$DIR/extracted_ds.jsonl}"

>"$OUT"

if command -v jq >/dev/null 2>&1; then
  for f in "$DIR"/*_raw_dataset.jsonl; do
    [ -e "$f" ] || continue
    jq -c 'select(has("issue_url") and .issue_url != null) | {org,repo,number,issue_url}' "$f" >>"$OUT"
  done
else
  for f in "$DIR"/*_raw_dataset.jsonl; do
    [ -e "$f" ] || continue
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
      printf '{"org":"%s","repo":"%s","number":%s,"issue_url":"%s"}\n' "$org" "$repo" "$number" "$issue_url" >>"$OUT"
    done < "$f"
  done
fi
