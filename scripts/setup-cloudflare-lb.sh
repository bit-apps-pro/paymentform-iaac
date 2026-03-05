#!/bin/bash
# Cloudflare Load Balancer Setup Script
# Run this after deploying all regions

set -e

echo "=== Cloudflare Load Balancer Setup ==="
echo ""

# Check if cf-cli is installed
if ! command -v cf-cli &> /dev/null; then
    echo "Installing cloudflared..."
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi

# Get inputs
read -p "Enter Cloudflare API Token: " CF_API_TOKEN
read -p "Enter Zone ID: " ZONE_ID
read -p "Enter Account ID: " ACCOUNT_ID
read -p "Enter Load Balancer Name (e.g., api.paymentform.io): " LB_NAME

read -p "Enter US Pool Origin IP: " US_IP
read -p "Enter EU Pool Origin IP: " EU_IP
read -p "Enter AU Pool Origin IP: " AU_IP

echo ""
echo "Creating Health Monitor..."
MONITOR=$(cf api /accounts/$ACCOUNT_ID/load_balancers/monitors \
    -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "description": "API Health Check",
        "type": "https",
        "method": "GET",
        "path": "/health",
        "timeout": 5,
        "interval": 30,
        "retries": 3
    }' 2>/dev/null | jq -r '.result.id')

echo "Monitor ID: $MONITOR"

echo ""
echo "Creating US Pool..."
US_POOL=$(cf api /accounts/$ACCOUNT_ID/load_balancers/pools \
    -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"us-pool\",
        \"description\": \"US Region Pool\",
        \"enabled\": true,
        \"minimum_origins\": 1,
        \"monitor\": \"$MONITOR\",
        \"origins\": [{\"name\": \"us-origin\", \"address\": \"$US_IP\", \"enabled\": true}]
    }" 2>/dev/null | jq -r '.result.id')

echo "US Pool ID: $US_POOL"

echo ""
echo "Creating EU Pool..."
EU_POOL=$(cf api /accounts/$ACCOUNT_ID/load_balancers/pools \
    -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"eu-pool\",
        \"description\": \"EU Region Pool\",
        \"enabled\": true,
        \"minimum_origins\": 1,
        \"monitor\": \"$MONITOR\",
        \"origins\": [{\"name\": \"eu-origin\", \"address\": \"$EU_IP\", \"enabled\": true}]
    }" 2>/dev/null | jq -r '.result.id')

echo "EU Pool ID: $EU_POOL"

echo ""
echo "Creating AU Pool..."
AU_POOL=$(cf api /accounts/$ACCOUNT_ID/load_balancers/pools \
    -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"au-pool\",
        \"description\": \"AU Region Pool\",
        \"enabled\": true,
        \"minimum_origins\": 1,
        \"monitor\": \"$MONITOR\",
        \"origins\": [{\"name\": \"au-origin\", \"address\": \"$AU_IP\", \"enabled\": true}]
    }" 2>/dev/null | jq -r '.result.id')

echo "AU Pool ID: $AU_POOL"

echo ""
echo "Creating Load Balancer..."
cf api /accounts/$ACCOUNT_ID/load_balancers \
    -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$LB_NAME\",
        \"description\": \"Multi-region load balancer\",
        \"enabled\": true,
        \"fallback_pool\": \"$US_POOL\",
        \"default_pools\": [\"$US_POOL\"],
        \"region_pools\": {
            \"WNAM\": [\"$US_POOL\"],
            \"ENAM\": [\"$US_POOL\"],
            \"WEU\": [\"$EU_POOL\"],
            \"EEU\": [\"$EU_POOL\"],
            \"SEAS\": [\"$AU_POOL\"],
            \"NEAS\": [\"$AU_POOL\"]
        },
        \"steering_policy\": \"geo\",
        \"proxied\": true
    }" 2>/dev/null

echo ""
echo "=== Load Balancer Created Successfully ==="
echo ""
echo "Pool IDs:"
echo "  US: $US_POOL"
echo "  EU: $EU_POOL"
echo "  AU: $AU_POOL"
