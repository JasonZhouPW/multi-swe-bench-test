#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <PATCH_DIR> $1 <OUTPUT>"
    exit 1
fi

PATCH_DIR="$1"
OUTPUT="$2"

# 清空旧文件
# mkdir -p "$(dirname "$OUTPUT")"
> "$OUTPUT"

shopt -s nullglob
for patch_file in "$PATCH_DIR"/*.patch; do
    base=$(basename "$patch_file")
    name="${base%.patch}"
    if [[ "$name" =~ ^([^_]+)_(.+)_([0-9]+)_([0-9]+)$ ]]; then
        org="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        prNumber="${BASH_REMATCH[3]}"
        issueNumber="${BASH_REMATCH[4]}"
    else
        continue
    fi

    if command -v jq >/dev/null 2>&1; then
        patch_content=$(jq -Rs . < "$patch_file")
    else
        patch_content=$(python3 - <<'PY' < "$patch_file"
import json,sys
print(json.dumps(sys.stdin.read()))
PY
)
    fi

    echo "{\"org\":\"$org\",\"repo\":\"$repo\",\"number\":$prNumber,\"fix_patch\":$patch_content}" >> "$OUTPUT"
done

echo "Generated $OUTPUT"
