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

ensure_docker_compose() {
  # docker-compose-plugin ships with current Docker on Amazon Linux 2023.
  # Guard against older AMIs by attempting an install if `docker compose` is
  # missing. Never fail userdata over this — fall through and let the compose
  # command surface a clear error.
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  log "docker compose plugin missing; attempting install"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y docker-compose-plugin || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y docker-compose-plugin || true
  fi
}

log "Starting container deployment"

ENV_PATH="/etc/app.env"
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

# -----------------------------------------------------------------------------
# Sockudo config — only written when the sidecar is enabled. Terraform passes
# an empty string when disabled so this block no-ops cleanly on renderer
# instances and on backend instances that opt out.
# -----------------------------------------------------------------------------
SOCKUDO_CONFIG_DIR="/etc/sockudo"
SOCKUDO_CONFIG_PATH="$SOCKUDO_CONFIG_DIR/config.json"
mkdir -p "$SOCKUDO_CONFIG_DIR"
SOCKUDO_CONFIG_CONTENT=$(cat <<'SOCKUDO_EOF'
${sockudo_config_content}
SOCKUDO_EOF
)
if [ -n "$SOCKUDO_CONFIG_CONTENT" ]; then
  log "Writing sockudo config to $SOCKUDO_CONFIG_PATH"
  printf '%s\n' "$SOCKUDO_CONFIG_CONTENT" > "$SOCKUDO_CONFIG_PATH"
  chmod 0644 "$SOCKUDO_CONFIG_PATH"
else
  log "Sockudo disabled — skipping config write"
  rm -f "$SOCKUDO_CONFIG_PATH"
fi

# -----------------------------------------------------------------------------
# Compose file. Terraform-side $${...} interpolation already happened; the
# quoted heredoc below disables shell-level expansion so YAML $${...} (none
# currently) and $$ sequences pass through untouched.
# -----------------------------------------------------------------------------
COMPOSE_DIR="/opt/paymentform"
COMPOSE_PATH="$COMPOSE_DIR/compose.yml"
mkdir -p "$COMPOSE_DIR"
log "Writing compose file to $COMPOSE_PATH"
cat > "$COMPOSE_PATH" <<'COMPOSE_EOF'
${compose_yml_content}
COMPOSE_EOF

# Legacy deploy script kept available for ad-hoc debugging but no longer
# invoked from userdata — the compose flow below replaces it. ${deploy_script_content}
# is intentionally read into a sentinel file so future change-detection still
# works for callers that supply it.
if [ -n "${deploy_script_content}" ]; then
  log "Writing legacy deploy script for reference (unused at boot)"
  cat > /usr/local/bin/deploy-ec2.sh <<'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
  chmod +x /usr/local/bin/deploy-ec2.sh
fi

ensure_docker_compose

log "Pulling container images via docker compose"
cd "$COMPOSE_DIR"
docker compose pull

log "Starting containers (waiting for healthchecks)"
# --wait blocks until every service with a healthcheck reports healthy. If
# backend never comes up, userdata fails loudly here instead of leaving a
# silently-broken instance attached to the ALB.
docker compose up -d --remove-orphans --wait

log "Containers started successfully"

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
