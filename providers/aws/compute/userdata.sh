#!/bin/bash
set -e

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

configure_ecs() {
  log "Configuring ECS cluster: ${ecs_cluster_name}"
  echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config
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

start_backend_service() {
  log "Starting backend service..."
  
  docker pull ghcr.io/bit-apps-pro/paymentform-backend:latest
  
  docker run -d \
    --name paymentform-backend \
    --restart unless-stopped \
    --env-file /etc/app.env \
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
  install_docker
  create_volumes
  authenticate_ghcr
  fetch_ssm_parameters
  
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
