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

log "Writing deploy script"
cat > /usr/local/bin/deploy-ec2.sh << 'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
chmod +x /usr/local/bin/deploy-ec2.sh

log "Executing deploy script"
/usr/local/bin/deploy-ec2.sh

log "Container started successfully"

# CloudWatch Agent — publishes mem_used_percent to CWAgent namespace so the ASG
# can scale on memory (the relevant signal for SSR + Caddy on-demand TLS workloads).
# aggregation_dimensions rolls per-instance metrics up by AutoScalingGroupName so
# a single alarm covers the whole group.
log "Installing CloudWatch Agent"
ARCH=$(uname -m)
if command -v rpm >/dev/null 2>&1 && ! command -v dpkg >/dev/null 2>&1; then
  # Amazon Linux 2 / AL2023 — rpm-based
  case "$ARCH" in
    aarch64) CWA_URL=https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm ;;
    x86_64)  CWA_URL=https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm ;;
  esac
  curl -fsSL "$CWA_URL" -o /tmp/cwa.rpm
  rpm -U /tmp/cwa.rpm || rpm -i /tmp/cwa.rpm
else
  # Ubuntu/Debian — deb-based
  case "$ARCH" in
    aarch64) CWA_URL=https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb ;;
    x86_64)  CWA_URL=https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb ;;
  esac
  curl -fsSL "$CWA_URL" -o /tmp/cwa.deb
  dpkg -i /tmp/cwa.deb
fi

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWA'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}"
    },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWA

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

log "CloudWatch Agent started"

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
