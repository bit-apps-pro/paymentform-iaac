#!/bin/bash
set -e

log() {
 echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

authenticate_ghcr() {
log "Authenticating with GHCR..."
GHCR_TOKEN=$(aws ssm get-parameter \
  --name "/paymentform/${environment}/backend/GHCR_TOKEN" \
  --with-decryption \
  --region ${region} \
  --query Parameter.Value \
  --output text 2>/dev/null || echo "")

if [ -n "$GHCR_TOKEN" ]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u ${ghcr_username} --password-stdin || true
  log "GHCR authentication successful"
else
  log "WARNING: GHCR_TOKEN not found; public images only"
fi
}

log "Starting container deployment"

ENV_PATH="/etc/${service_type}.env"
> "$ENV_PATH"

CADDY_ENV_PATH="/etc/caddy.env"
> "$CADDY_ENV_PATH"

# Write environment variables with conditional double-quoting
# Values containing spaces or # (comment char) are wrapped in double quotes
quote_env_value() {
  local val="$1"
  case "$val" in
    *[[:space:]\#\"\$\&\;]*)
      printf '"%s"' "$val"
      ;;
    *)
      printf '%s' "$val"
      ;;
  esac
}

while IFS='=' read -r key value; do
  [ -z "$key" ] && continue
  printf '%s=%s\n' "$key" "$(quote_env_value "$value")" >> "$ENV_PATH"
done <<EOF
${container_env_vars}
EOF

while IFS='=' read -r key value; do
  [ -z "$key" ] && continue
  printf '%s=%s\n' "$key" "$(quote_env_value "$value")" >> "$CADDY_ENV_PATH"
done <<EOF
${caddy_env_vars}
EOF

while IFS='=' read -r key value; do
  [ -z "$key" ] && continue
  case "$value" in
    *[[:space:]\#]*)
      echo "$${key}=\"$${value}\"" >> "$CADDY_ENV_PATH"
      ;;
    *)
      echo "$${key}=$${value}" >> "$CADDY_ENV_PATH"
      ;;
  esac
done <<EOF
${caddy_env_vars}
EOF

echo "AUTO_SSL=${auto_ssl}" >> "$CADDY_ENV_PATH"

authenticate_ghcr

log "Writing deploy script"
cat > /usr/local/bin/deploy-ec2.sh << 'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
chmod +x /usr/local/bin/deploy-ec2.sh

log "Executing deploy script"
/usr/local/bin/deploy-ec2.sh

log "Container started successfully"

%{ if tunnel_token != "" ~}
log "Starting cloudflared tunnel connector"
docker stop cloudflared || true
docker rm cloudflared || true
docker run -d \
  --name cloudflared \
  --restart unless-stopped \
  --network=host \
  cloudflare/cloudflared:latest tunnel --no-autoupdate run \
  --token ${tunnel_token}
log "cloudflared started"
%{ endif ~}
