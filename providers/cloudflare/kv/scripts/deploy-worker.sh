#!/bin/bash
set -e

NAMESPACE_ID="$1"
WORKER_PATH=$(realpath "$2")
ENV="$3"
ACCOUNT_ID="$4"
KV_STORE_API_TOKEN="$5"

if [ -z "$NAMESPACE_ID" ]; then
    echo "ERROR: NAMESPACE_ID is empty, skipping deployment"
    exit 0
fi

WRANGLER_CONFIG=""
for f in wrangler.toml wrangler.jsonc wrangler.json; do
    if [ -f "$WORKER_PATH/$f" ]; then
        WRANGLER_CONFIG="$WORKER_PATH/$f"
        break
    fi
done

if [ -z "$WRANGLER_CONFIG" ]; then
    echo "ERROR: wrangler.toml / wrangler.jsonc / wrangler.json not found at $WORKER_PATH"
    exit 1
fi

echo "Using wrangler config: $WRANGLER_CONFIG"
echo "Updating with namespace ID: $NAMESPACE_ID"

KV_NAMESPACE_ID=""
KV_PREVIEW_ID=""

if [ "$ENV" = "prod-us" ] || [ "$ENV" = "prod" ]; then
    KV_NAMESPACE_ID="$NAMESPACE_ID"
    KV_PREVIEW_ID="$NAMESPACE_ID"
fi

cd "$WORKER_PATH"

if [ -n "$KV_STORE_API_TOKEN" ]; then
    echo "Setting KV_STORE_API_TOKEN secret..."
    echo "$KV_STORE_API_TOKEN" | wrangler secret put KV_STORE_API_TOKEN --env prod 2>/dev/null || true
fi

if [ -n "$KV_NAMESPACE_ID" ]; then
    echo "Updating kv_namespaces in wrangler config..."
    sed -i "s|id = \".*\"|id = \"$KV_NAMESPACE_ID\"|" "$WRANGLER_CONFIG" 2>/dev/null || true
    sed -i "s|\"id\": \".*\"|\"id\": \"$KV_NAMESPACE_ID\"|" "$WRANGLER_CONFIG" 2>/dev/null || true
fi

echo "Deploying kv-store worker..."
cd "$WORKER_PATH"

if ! command -v wrangler &> /dev/null; then
    echo "Installing wrangler..."
    pnpm install -g wrangler
fi

wrangler deploy --env prod

echo "KV Store deployed successfully"
