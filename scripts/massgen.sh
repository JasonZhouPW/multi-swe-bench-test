#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 [CONFIG] ISSUE_URL OUTPUT_FILE

Positional arguments:
  CONFIG       Path to config.yaml (optional). Default: ./config.yaml
  ISSUE_URL    URL of the issue (required)
  OUTPUT_FILE  File path to write JSON result (required)

Examples:
  $0 https://github.com/owner/repo/issues/123 output.json           # uses ./config.yaml
  $0 ./config.yaml https://github.com/owner/repo/issues/123 out.json
USAGE
  exit 1
}

# Parse positional parameters
if [[ $# -eq 2 ]]; then
  CONFIG="./config.yaml"
  ISSUE_URL="$1"
  OUTPUT_FILE="$2"
elif [[ $# -eq 3 ]]; then
  CONFIG="$1"
  ISSUE_URL="$2"
  OUTPUT_FILE="$3"
else
  usage
fi

# Basic validation
if [[ -z "$ISSUE_URL" || -z "$OUTPUT_FILE" ]]; then
  echo "ERROR: ISSUE_URL and OUTPUT_FILE are required." >&2
  usage
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Warning: config file '$CONFIG' not found." >&2
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Running massgen with config='$CONFIG' issue_url='$ISSUE_URL' output_file='$OUTPUT_FILE'"

# Ensure ZAI_API_KEY env var is set (default placeholder 'xxx')
export ZAI_API_KEY="${ZAI_API_KEY:-xxx}"
if [[ "${ZAI_API_KEY}" == "xxx" ]]; then
  echo "Warning: ZAI_API_KEY is set to placeholder 'xxx'. Set ZAI_API_KEY in your environment for real runs." >&2
fi

# Build the prompt the user requested
PROMPT="fix ${ISSUE_URL} and save the ${OUTPUT_FILE} in git patch format in current folder"

# Require an installed 'massgen' CLI in PATH
if command -v massgen >/dev/null 2>&1; then
  echo "Found 'massgen' CLI in PATH."
  CMD=(massgen --config "$CONFIG" --no-display "$PROMPT")
else
  echo "ERROR: 'massgen' CLI not found in PATH. Please install massgen and ensure it's available in PATH." >&2
  exit 2
fi

# Invoke massgen, stream output to console, and save to the output file
# Use 'tee' to write to file while still showing stdout/stderr in console
"${CMD[@]}" 2>&1 | tee "$OUTPUT_FILE"
# Capture the exit code of the massgen command (first element of PIPESTATUS)
EXIT_CODE=${PIPESTATUS[0]}
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "massgen invocation failed with exit code $EXIT_CODE" >&2
  exit $EXIT_CODE
fi

# Make patch files in current folder explicit: if massgen wrote files instead of stdout, ensure
# the requested $OUTPUT_FILE exists. Warn if not.
if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "Warning: expected output file '$OUTPUT_FILE' not found after massgen. Inspect stdout or massgen behavior." >&2
else
  echo "Output saved to $OUTPUT_FILE"
fi
