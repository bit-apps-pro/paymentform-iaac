#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

needs_quotes() {
  case "$1" in
    *[[:space:]\#\"\$\&\;]*) return 0 ;;
    *) return 1 ;;
  esac
}

log "Starting Hetzner server setup with Nginx reverse proxy"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

%{ if os_user_public_key != "" ~}
log "Creating OS user: ${os_username}"
id "${os_username}" &>/dev/null || useradd -m -s /bin/bash "${os_username} && passwd -d ${os_username}"

for grp in docker; do
  if getent group "$grp" >/dev/null 2>&1; then
    usermod -aG "$grp" "${os_username}"
  fi
done

mkdir -p /home/${os_username}/.ssh
chmod 700 /home/${os_username}/.ssh
cat > /home/${os_username}/.ssh/authorized_keys <<'SSHEOF'
${os_user_public_key}
SSHEOF
chmod 600 /home/${os_username}/.ssh/authorized_keys
chown -R ${os_username}:${os_username} /home/${os_username}/.ssh

log "OS user ${os_username} created with SSH key"
%{ endif ~}

systemctl enable docker
systemctl start docker

log "Installing Docker Compose"
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

log "Logging into GHCR"
echo "${ghcr_token}" | docker login ghcr.io -u "${ghcr_username}" --password-stdin
${os_username}
log "Creating app directories"
mkdir -p /opt/app/data/backend /opt/app/data/renderer /opt/app/data/valkey /opt/app/data/caddy /opt/app/conf
echo "data/*"  > /opt/app/.dockerignore
chown -R ${os_username}:docker /opt/app

write_env_file() {
  local file="$1"
  shift
  > "$file"
  while [[ $# -gt 0 ]]; do
    local key="$1"
    local val="$2"
    shift 2
    [[ -z "$val" ]] && continue
    if needs_quotes "$val"; then
      printf '%s="%s"\n' "$key" "$val" >> "$file"
    else
      printf '%s=%s\n' "$key" "$val" >> "$file"
    fi
  done
}

log "Writing backend environment file"
write_env_file /opt/app/backend.env \
%{ for key, value in backend_container_env_vars ~}
%{ if value != null ~}
  "${key}" "${value}" \
%{ endif ~}
%{ endfor ~}
  || true

%{ if renderer_container_image != "" ~}
log "Writing renderer environment file"
write_env_file /opt/app/renderer.env \
%{ for key, value in renderer_container_env_vars ~}
%{ if value != null ~}
  "${key}" "${value}" \
%{ endif ~}
%{ endfor ~}
  || true
%{ endif ~}

log "Writing Caddy environment file"
write_env_file /opt/app/caddy.env \
%{ for key, value in caddy_env_vars ~}
%{ if value != null ~}
  "${key}" "${value}" \
%{ endif ~}
%{ endfor ~}
  || true

log "Creating Nginx configuration"
mkdir -p /opt/nginx
cat > /opt/app/conf/nginx.conf <<'NGINXEOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

stream {
    map $ssl_preread_server_name $upstream {
        api.${traefik_host}    backend;
        api-eu.${traefik_host} backend;
        api-ap.${traefik_host} backend;
        default                renderer;
    }

    upstream backend {
        server backend:443;
    }

    upstream renderer {
        server renderer:443;
    }

    server {
        listen 443;
        proxy_pass $upstream;
        ssl_preread on;
    }
}

http {
    upstream backend_http {
        server backend:80;
    }

    upstream renderer_http {
        server renderer:80;
    }

    server {
        listen 80;
        server_name api.${traefik_host} api-eu.${traefik_host} api-ap.${traefik_host};

        location / {
            proxy_pass http://backend_http;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://renderer_http;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
NGINXEOF

log "Generating docker-compose.yml"
cat > /opt/app/docker-compose.yml <<'COMPOSEEOF'
services:
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/app/conf/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - traefik-public
  backend:
    image: ${container_image}
    restart: unless-stopped
    env_file:
      - /opt/app/caddy.env
    volumes:
      - /opt/app/data/caddy/data:/data/caddy
      - /opt/app/data/caddy/config:/config/caddy
      - /opt/app/backend.env:/app/.env:ro
    networks:
      - traefik-public
    depends_on:
      - valkey
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:80/up"]
      interval: 30s
      timeout: 10s
      start_period: 60s
      retries: 3
%{ if renderer_container_image != "" ~}
  renderer:
    image: ${renderer_container_image}
    restart: unless-stopped
    env_file:
      - /opt/app/caddy.env
    volumes:
      - /opt/app/data/caddy/data:/data/caddy
      - /opt/app/data/caddy/config:/config/caddy
      - /opt/app/renderer.env:/app/.env:ro
    networks:
      - traefik-public
    depends_on:
      - backend
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:80/health"]
      interval: 30s
      timeout: 10s
      start_period: 60s
      retries: 3
%{ endif ~}

  valkey:
    image: valkey/valkey:latest
    restart: unless-stopped
    command: valkey-server --appendonly yes --requirepass ${valkey_password}
    volumes:
      - /opt/app/data/valkey:/data
    networks:
      - traefik-public
    healthcheck:
      test: ["CMD", "valkey-cli", "-a", "${valkey_password}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
networks:
  traefik-public:
    driver: bridge
COMPOSEEOF

%{ if db_host != "" ~}
log "Setting DB_HOST to direct database host"
sed -i 's/^DB_HOST=.*/DB_HOST=${db_host}/' /opt/app/backend.env
%{ endif ~}

log "Writing deploy script"
cat > /usr/local/bin/deploy-hetzner.sh << 'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
chmod +x /usr/local/bin/deploy-hetzner.sh

log "Executing deploy script"
/usr/local/bin/deploy-hetzner.sh

log "Hetzner server setup complete"
