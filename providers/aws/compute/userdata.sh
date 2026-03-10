#!/bin/bash
set -e

log() {
 echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

log "Authenticating with GHCR..."

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

configure_pgbouncer() {
  if [ "${enable_pgbouncer}" = "true" ]; then
    
    mkdir -p /etc/pgbouncer /var/log/pgbouncer
    
    cat > /etc/pgbouncer/pgbouncer.ini <<EOF
[databases]
paymentform = host=${db_host} port=5432 dbname=${db_name}

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
log_connections = 0
log_disconnections = 0
log_pooler_errors = 1
admin_users = postgres
pidfile = /var/run/pgbouncer/pgbouncer.pid
logfile = /var/log/pgbouncer/pgbouncer.log
EOF

    cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "${db_password}"
EOF

    mkdir -p /var/run/pgbouncer
    chown pgbouncer:pgbouncer /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt /var/run/pgbouncer
    chmod 640 /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt
    
    pkill -f pgbouncer || true
    sudo -u pgbouncer pgbouncer -d /etc/pgbouncer/pgbouncer.ini
    
    log "PgBouncer configured and started"
  fi
}

log "Starting container deployment"

ENV_PATH="/etc/app.env"
> $ENV_PATH

echo "${container_env_vars}" >> $ENV_PATH

IMAGE=$(aws ssm get-parameter \
 --name "/paymentform/${environment}/backend/IMAGE" \
 --region ${region} \
 --query Parameter.Value \
 --output text 2>/dev/null)

log "Pulling image $IMAGE"

authenticate_ghcr
docker pull $IMAGE

docker stop paymentform-${service_type} || true
docker rm paymentform-${service_type} || true

configure_pgbouncer

docker run -d \
  --name paymentform-${service_type} \
  --network=host \
  --restart unless-stopped \
  --env-file $ENV_PATH \
  -p 80:80 \
  -p 443:443 \
  -v /data/caddy:/data/caddy \
  -v /config/caddy:/config/caddy \
  $IMAGE

log "Container started successfully"