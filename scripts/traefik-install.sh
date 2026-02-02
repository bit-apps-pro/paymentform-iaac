#!/bin/bash
# EC2 User Data Script for Traefik Installation
# This script runs on first boot to set up Docker and Traefik

set -euo pipefail

# Log everything to file and console
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "Starting EC2 user-data script at $(date)"

# Update system packages
apt-get update -y
apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install Docker Compose
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="2.24.0"
curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Traefik
echo "Installing Traefik..."
TRAEFIK_VERSION="3.0.0"
curl -L "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_amd64.tar.gz" -o /tmp/traefik.tar.gz
tar -xzf /tmp/traefik.tar.gz -C /tmp/
mv /tmp/traefik /usr/local/bin/traefik
chmod +x /usr/local/bin/traefik
rm /tmp/traefik.tar.gz

# Create Traefik directories
mkdir -p /etc/traefik/dynamic
mkdir -p /var/log/traefik
touch /etc/traefik/acme.json
chmod 600 /etc/traefik/acme.json

# Configure Cloudflare credentials (from AWS Secrets Manager)
echo "Configuring Cloudflare credentials..."
export CF_API_EMAIL="${cloudflare_email}"
export CF_DNS_API_TOKEN="${cloudflare_api_token}"

# Create Traefik static configuration
cat > /etc/traefik/traefik.yml <<'EOF'
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: cloudflare
    forwardedHeaders:
      trustedIPs:
        - "173.245.48.0/20"
        - "103.21.244.0/22"
        - "103.22.200.0/22"
        - "103.31.4.0/22"
        - "141.101.64.0/18"
        - "108.162.192.0/18"
        - "190.93.240.0/20"
        - "188.114.96.0/20"
        - "197.234.240.0/22"
        - "198.41.128.0/17"
        - "162.158.0.0/15"
        - "104.16.0.0/13"
        - "104.24.0.0/14"
        - "172.64.0.0/13"
        - "131.0.72.0/22"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    watch: true
  
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificateResolvers:
  cloudflare:
    acme:
      email: "${acme_email}"
      storage: /etc/traefik/acme.json
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 30
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"

log:
  level: INFO
  format: json
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log
  format: json

ping:
  entryPoint: websecure
EOF

# Create Traefik systemd service
cat > /etc/systemd/system/traefik.service <<'EOF'
[Unit]
Description=Traefik Reverse Proxy
Documentation=https://doc.traefik.io/traefik/
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=notify
EnvironmentFile=/etc/traefik/traefik.env
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.yml
Restart=on-failure
RestartSec=10s

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/traefik/acme.json /var/log/traefik
PrivateTmp=true

StandardOutput=journal
StandardError=journal

LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF

# Create environment file for Traefik
cat > /etc/traefik/traefik.env <<EOF
CF_API_EMAIL=${cloudflare_email}
CF_DNS_API_TOKEN=${cloudflare_api_token}
EOF
chmod 600 /etc/traefik/traefik.env

# Configure logrotate for Traefik
cat > /etc/logrotate.d/traefik <<'EOF'
/var/log/traefik/*.log {
  daily
  rotate 14
  compress
  delaycompress
  notifempty
  create 0640 root root
  sharedscripts
  postrotate
    systemctl reload traefik > /dev/null 2>&1 || true
  endscript
}
EOF

# Enable and start Traefik
systemctl daemon-reload
systemctl enable traefik
systemctl start traefik

# Configure GHCR authentication
echo "Configuring GitHub Container Registry authentication..."
mkdir -p /root/.docker
cat > /root/.docker/config.json <<EOF
{
  "auths": {
    "ghcr.io": {
      "auth": "${ghcr_token}"
    }
  }
}
EOF
chmod 600 /root/.docker/config.json

# Install CloudWatch agent (optional)
if [ "${install_cloudwatch}" = "true" ]; then
  echo "Installing CloudWatch agent..."
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  dpkg -i -E ./amazon-cloudwatch-agent.deb
  rm amazon-cloudwatch-agent.deb
fi

echo "EC2 user-data script completed at $(date)"
echo "Traefik status:"
systemctl status traefik --no-pager

echo "Docker status:"
systemctl status docker --no-pager
