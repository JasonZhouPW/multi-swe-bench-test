#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="${1:?usage: $0 <work-dir> [jsonl_path]}"
JSONL="${2:-$WORK_DIR/extracted_ds.jsonl}"
LOG_FILE="$WORK_DIR/massgen_run.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="$SCRIPT_DIR/massgen.yaml"
PATCH_DIR="$WORK_DIR/patches_massgen"
MASSGEN_SH="$SCRIPT_DIR/massgen.sh"
DEST_FOLDER="./patches/"

mkdir -p "$PATCH_DIR"

echo "config: $CFG"
if [[ ! -f "$MASSGEN_SH" ]]; then
  echo "ERROR: massgen runner not found at $MASSGEN_SH" >&2
  exit 2
fi

if command -v jq >/dev/null 2>&1; then
  jq -r 'select(has("org") and has("repo") and has("number") and has("issue_url") and .issue_url != null) | [.org,.repo,.number,.issue_url] | @tsv' "$JSONL" |
  while IFS=$'\t' read -r org repo number issue_url; do
    echo "Processing: $org/$repo #$number -> $issue_url"
    [ -n "$org" ] && [ -n "$repo" ] && [ -n "$issue_url" ] || continue

    if [[ "$issue_url" =~ ^https://api.github.com/repos/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
      issueNumber="${BASH_REMATCH[3]}"
      issue_url="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/issues/${BASH_REMATCH[3]}"
    fi

    out_file="$PATCH_DIR/${org}_${repo}_${number}_${issueNumber}.patch"

    echo "Calling massgen for $issue_url -> $out_file"
    set +e
    "$MASSGEN_SH" "$CFG" "$issue_url" "$out_file"
    rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
      echo "massgen failed (exit $rc) for $issue_url"
      continue
    fi

    if [[ -f "$out_file" && -s "$out_file" ]]; then
      echo "Patch generated: $out_file"
    else
      echo "No patch produced for $issue_url (expected $out_file)" >&2
    fi
  done
else
  # fallback to pure-shell parsing
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$line" | grep -q '"issue_url"' || continue
    printf '%s' "$line" | grep -q '"issue_url"[[:space:]]*:[[:space:]]*null' && continue
    org=$(printf '%s' "$line" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')
    repo=$(printf '%s' "$line" | sed -n 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')
    number=$(printf '%s' "$line" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    issue_url=$(printf '%s' "$line" | sed -n 's/.*"issue_url"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')

    [ -n "$org" ] && [ -n "$repo" ] && [ -n "$number" ] && [ -n "$issue_url" ] || continue

    if [[ "$issue_url" =~ ^https://api.github.com/repos/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
      issueNumber="${BASH_REMATCH[3]}"
      issue_url="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/issues/${BASH_REMATCH[3]}"
    fi

    out_file="$PATCH_DIR/${org}_${repo}_${number}_${issueNumber}.patch"

    echo "Calling massgen for $issue_url -> $out_file"
    set +e
    "$MASSGEN_SH" "$CFG" "$issue_url" "$out_file"
    rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
      echo "massgen failed (exit $rc) for $issue_url"
      continue
    fi

    if [[ -f "$out_file" && -s "$out_file" ]]; then
      echo "Patch generated: $out_file"
      cp "$out_file" "$DEST_FOLDER"d
    else
      echo "No patch produced for $issue_url (expected $out_file)" >&2
    fi
  done < "$LOG_FILE"
fi
