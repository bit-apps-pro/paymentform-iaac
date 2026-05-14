#!/bin/bash
set -euo pipefail

PROVIDER=${1:-hetzner}
MODULE=${2:-}
OUTPUT_FILE=${3:-}

if [ -z "$MODULE" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "Usage: $0 <hetzner|aws> <module-name> <output-file>"
  echo ""
  echo "Examples:"
  echo "  $0 hetzner module.hetzner_backend_hel1 hetzner-userdata.sh"
  echo "  $0 aws module.paymentform_backend aws-userdata.sh"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed."
  echo "Install with: apt-get install jq  (Debian/Ubuntu)"
  echo "             brew install jq      (macOS)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../environments/prod"
OUT_PATH="$SCRIPT_DIR/../../$OUTPUT_FILE"

cd "$ENV_DIR"

echo "Extracting $PROVIDER userdata from state ($MODULE)..."

if [ "$PROVIDER" = "hetzner" ]; then
  tofu state pull | jq -r --arg mod "$MODULE" '
    .resources[]
    | select(.module == $mod and .type == "hcloud_server")
    | .instances[0].attributes.user_data
  ' > "$OUT_PATH"
elif [ "$PROVIDER" = "aws" ]; then
  tofu state pull | jq -r --arg mod "$MODULE" '
    .resources[]
    | select(.module == $mod and .type == "aws_launch_template")
    | .instances[0].attributes.user_data
  ' | base64 -d > "$OUT_PATH"
else
  echo "Error: Unknown provider '$PROVIDER'. Use 'hetzner' or 'aws'."
  exit 1
fi

if [ -s "$OUT_PATH" ] && [ "$(cat "$OUT_PATH")" != "null" ]; then
  echo "Created: $OUTPUT_FILE ($(wc -l < "$OUT_PATH") lines)"
else
  echo "Error: Failed to extract userdata. Resource may not exist in state yet."
  rm -f "$OUT_PATH"
  exit 1
fi
