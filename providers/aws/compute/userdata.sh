#!/bin/bash
set -e

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

configure_ecs() {
  log "Configuring ECS cluster: ${ecs_cluster_name}"
  echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config
}

install_pgbouncer() {
  if [ "${enable_pgbouncer}" = "true" ]; then
    log "Installing PgBouncer..."
    apt-get update -y
    apt-get install -y pgbouncer
    
    mkdir -p /etc/pgbouncer /var/log/pgbouncer
    
    cat > /etc/pgbouncer/pgbouncer.ini <<'EOF'
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
EOF

    cat > /etc/pgbouncer/userlist.txt <<'EOF'
"postgres" "${db_password}"
EOF

    chown pgbouncer:pgbouncer /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt
    chmod 640 /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt
    
    systemctl enable pgbouncer
    systemctl start pgbouncer
    
    log "PgBouncer installed and started"
  fi
}

install_docker() {
  log "Installing Docker and dependencies..."
  apt-get update -y
  apt-get install -y ca-certificates curl awscli jq
  
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  
  echo "deb [arch=$$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu \
    $$(. /etc/os-release && echo "$$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list
  
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io
  
  systemctl start docker
  systemctl enable docker
  usermod -a -G docker ubuntu
  
  log "Docker installed successfully"
}

create_volumes() {
  log "Creating Caddy persistence directories..."
  mkdir -p /data/caddy /config/caddy
  chmod 755 /data/caddy /config/caddy
}

authenticate_ghcr() {
  log "Authenticating with GHCR..."
  GHCR_TOKEN=$$(aws ssm get-parameter \
    --name "/app/$${environment}/backend/GHCR_TOKEN" \
    --with-decryption \
    --region $${region} \
    --query Parameter.Value \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$$GHCR_TOKEN" ]; then
    echo "$$GHCR_TOKEN" | docker login ghcr.io -u x-access-token --password-stdin || true
    log "GHCR authentication successful"
  else
    log "WARNING: GHCR_TOKEN not found; public images only"
  fi
}

fetch_ssm_parameters() {
  log "Fetching SSM parameters..."
  
  > /etc/app.env
  
  aws ssm get-parameters-by-path \
    --path "/app/$${environment}/backend/" \
    --recursive \
    --with-decryption \
    --region $${region} \
    --query 'Parameters[*].[Name,Value]' \
    --output text | while read name value; do
      param_name=$${name##*/}
      echo "$${param_name}=$${value}" >> /etc/app.env
    done
  
  echo "ENVIRONMENT=production" >> /etc/app.env
  echo "AWS_STORAGE_BUCKET=$${bucket_name}" >> /etc/app.env
  
  log "Environment file created at /etc/app.env"
}

write_container_env_vars() {
  if [ -n "$container_env_vars" ]; then
    log "Writing container env vars..."
    > /etc/container_env
    echo "$container_env_vars" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' >> /etc/container_env
    log "Container env vars written to /etc/container_env"
  fi
}

start_backend_service() {
  log "Starting backend service..."
  
  docker pull ghcr.io/bit-apps-pro/paymentform-backend:latest
  
  CONTAINER_ENV_FLAGS=""
  if [ -f /etc/container_env ]; then
    while IFS='=' read -r key value; do
      CONTAINER_ENV_FLAGS="$${CONTAINER_ENV_FLAGS} -e $${key}=$${value}"
    done < /etc/container_env
  fi
  
  docker run -d \
    --name paymentform-backend \
    --restart unless-stopped \
    --env-file /etc/app.env \
    $${CONTAINER_ENV_FLAGS} \
    -e "APP_DOMAIN=api.$${environment}.paymentform.io" \
    -e "ENVIRONMENT=production" \
    -p 80:80 \
    -p 443:443 \
    -v /data/caddy:/data/caddy \
    -v /config/caddy:/config/caddy \
    ghcr.io/bit-apps-pro/paymentform-backend:latest
  
  log "Backend container started"
}

start_renderer_service() {
  log "Starting renderer service..."
  
  docker pull ghcr.io/bit-apps-pro/paymentform-renderer:latest
  
  docker run -d \
    --name paymentform-renderer \
    --restart unless-stopped \
    --env-file /etc/app.env \
    -e "APP_DOMAIN=*.$$environment.paymentform.io" \
    -e "ENVIRONMENT=production" \
    -p 80:80 \
    -p 443:443 \
    -v /data/caddy:/data/caddy \
    -v /config/caddy:/config/caddy \
    ghcr.io/bit-apps-pro/paymentform-renderer:latest
  
  log "Renderer container started"
}

main() {
  log "=== EC2 Userdata Initialization Started ==="
  
  configure_ecs
  install_pgbouncer
  install_docker
  create_volumes
  authenticate_ghcr
  fetch_ssm_parameters
  write_container_env_vars
  
  if [ "$${service_type}" = "backend" ]; then
    start_backend_service
  elif [ "$${service_type}" = "renderer" ]; then
    start_renderer_service
  else
    log "ERROR: Invalid service_type '$${service_type}'. Must be 'backend' or 'renderer'."
    exit 1
  fi
  
  log "=== EC2 Userdata Initialization Completed ==="
}

main
