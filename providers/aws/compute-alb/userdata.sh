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

# Sockudo config is rendered inside the container by start.sh, reading
# REVERB_APP_{ID,KEY,SECRET} from the env_file. No host-side bind-mount —
# the prior /etc/sockudo/config.json write was the only reason this module
# needed templated JSON on disk.

# Legacy deploy script kept available for ad-hoc debugging but no longer
# invoked from userdata — the docker run flow below replaces it.
if [ -n "${deploy_script_content}" ]; then
  log "Writing legacy deploy script for reference (unused at boot)"
  cat > /usr/local/bin/deploy-ec2.sh <<'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
  chmod +x /usr/local/bin/deploy-ec2.sh
fi

CONTAINER_NAME="paymentform-backend"
BACKEND_IMAGE="${IMAGE}"

log "Pulling $BACKEND_IMAGE"
docker pull "$BACKEND_IMAGE"

# Idempotent boot: remove any prior container (e.g. AMI replacement / restart)
# before starting a fresh one. `|| true` keeps the cold-boot path quiet.
docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

log "Starting $CONTAINER_NAME"
docker run -d \
  --name "$CONTAINER_NAME" \
  --network host \
  --restart unless-stopped \
  --env-file /etc/app.env \
  -e CADDY_ENV_FILE=/etc/caddy.env \
  --health-cmd "curl -sf http://localhost:80/health" \
  --health-interval 30s \
  --health-timeout 10s \
  --health-start-period 60s \
  --health-retries 3 \
  --ulimit nofile=65536:65536 \
  "$BACKEND_IMAGE"

# Poll the container's healthcheck until it reports `healthy` so userdata
# fails loudly when the backend never finishes booting (mirrors the prior
# `docker compose up --wait` semantics). 60 × 5 s = 5 min ceiling matches
# start_period + healthcheck retries × interval budget.
log "Waiting for $CONTAINER_NAME healthcheck"
for i in $(seq 1 60); do
  status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)
  if [ "$status" = "healthy" ]; then
    log "$CONTAINER_NAME is healthy"
    break
  fi
  if [ "$i" -eq 60 ]; then
    log "ERROR: $CONTAINER_NAME never reached healthy (last status: $status)"
    docker logs --tail 200 "$CONTAINER_NAME" || true
    exit 1
  fi
  sleep 5
done

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
