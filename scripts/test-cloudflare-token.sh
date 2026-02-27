#!/bin/bash
# Test Cloudflare API token

# Check if token is set
if [ -z "$TF_VAR_cloudflare_api_token" ]; then
    echo "❌ TF_VAR_cloudflare_api_token is not set"
    echo ""
    echo "Set it with:"
    echo "  export TF_VAR_cloudflare_api_token=\"your-40-char-token\""
    exit 1
fi

# Check token length
TOKEN_LENGTH=${#TF_VAR_cloudflare_api_token}
if [ "$TOKEN_LENGTH" -ne 40 ]; then
    echo "❌ Token length is $TOKEN_LENGTH (should be 40)"
    echo "   Check if you copied the token correctly"
    exit 1
fi

echo "✓ Token length is correct (40 characters)"

# Check if account ID is set
if [ -z "$TF_VAR_cloudflare_account_id" ]; then
    echo "❌ TF_VAR_cloudflare_account_id is not set"
    echo ""
    echo "Set it with:"
    echo "  export TF_VAR_cloudflare_account_id=\"your-account-id\""
    exit 1
fi

echo "✓ Testing API token with Cloudflare..."

# Test the token
RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${TF_VAR_cloudflare_account_id}" \
  -H "Authorization: Bearer ${TF_VAR_cloudflare_api_token}")

SUCCESS=$(echo "$RESPONSE" | jq -r '.success')

if [ "$SUCCESS" = "true" ]; then
    echo "✅ Cloudflare API token is valid!"
    ACCOUNT_NAME=$(echo "$RESPONSE" | jq -r '.result.name')
    echo "   Account: $ACCOUNT_NAME"
    echo ""
    echo "You can now run:"
    echo "  AWS_PROFILE=anra make apply ENV=sandbox"
else
    echo "❌ Cloudflare API token is invalid"
    echo ""
    echo "Response:"
    echo "$RESPONSE" | jq '.'
    echo ""
    echo "Check:"
    echo "  1. Token is copied correctly (no extra spaces)"
    echo "  2. Token has not expired"
    echo "  3. Token has correct permissions"
    exit 1
fi
