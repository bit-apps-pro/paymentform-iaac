resource "null_resource" "turso_create" {
  # Re-run when inputs change
  triggers = {
    environment        = var.environment
    resource_prefix    = var.resource_prefix
    turso_api_token    = var.turso_api_token
    turso_auth_token   = var.turso_auth_token
    turso_organization = var.turso_organization
    turso_group        = var.turso_group
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail

if ! command -v turso >/dev/null 2>&1; then
  echo "turso CLI not found; skipping Turso self-managed creation."
  exit 0
fi
if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found; provisioner requires aws CLI to store SSM parameters"
  exit 1
fi

export TURSO_API_TOKEN='${var.turso_api_token}'
export TURSO_AUTH_TOKEN='${var.turso_auth_token}'

for short in tenants analytics backup; do
  db_name="${var.resource_prefix}-$short"
  echo "Creating Turso database: $db_name (idempotent)"
  # Attempt to create database; if it already exists, continue
  turso db create "$db_name" --org "${var.turso_organization}" || true

  # Attempt to create an access token and retrieve a libsql URL. The exact turso CLI
  # output varies; we attempt to capture something useful. These commands are best-effort
  # and the provisioner does not fail on non-critical failures.
  token_output=$(turso db token create "$db_name" --org "${var.turso_organization}" --json 2>/dev/null || true)
  conn_output=$(turso db connection-string "$db_name" --org "${var.turso_organization}" --format libsql 2>/dev/null || true)

  # Fallbacks if commands didn't return values
  token=$(echo "$token_output" | jq -r '.token' 2>/dev/null || true)
  url=$(echo "$conn_output" | tr -d '\n' || true)

  # Fallback to name-based libsql URL if CLI didn't provide one
  if [ -z "$url" ]; then
    url="libsql://${db_name}-${var.turso_organization}.turso.io"
  fi

  # Parameter names
  upper=$(echo "$short" | tr '[:lower:]' '[:upper:]')
  param_url="/app/${var.environment}/backend/TURSO_${upper}_DB_URL"
  param_token="/app/${var.environment}/backend/TURSO_${upper}_DB_TOKEN"

  echo "Storing DB URL to SSM: $param_url"
  aws ssm put-parameter --name "$param_url" --value "$url" --type SecureString --overwrite --region "${var.region}" $( [ -n "${var.kms_key_id}" ] && echo "--key-id ${var.kms_key_id}" ) || true

  if [ -n "$token" ]; then
    echo "Storing DB token to SSM: $param_token"
    aws ssm put-parameter --name "$param_token" --value "$token" --type SecureString --overwrite --region "${var.region}" $( [ -n "${var.kms_key_id}" ] && echo "--key-id ${var.kms_key_id}" ) || true
  else
    echo "No token available for $db_name; skipping token SSM write."
  fi

done
EOT
  }
}