# Traefik Cloud Setup Guide

This guide covers deploying Traefik as a reverse proxy on EC2 instances in AWS, integrated with Cloudflare.

## Architecture

```
Internet → Cloudflare → EC2 (Traefik) → Docker Containers
```

- **Cloudflare**: Edge SSL/TLS, WAF, DDoS protection, Load Balancing
- **Traefik**: Service discovery, routing, Let's Encrypt certificates
- **Docker**: Container orchestration with Docker Compose

## Prerequisites

- EC2 instances deployed in AWS
- Cloudflare configured (see [cloudflare-setup.md](./cloudflare-setup.md))
- Docker and Docker Compose installed
- Cloudflare API token for DNS challenge

## Installation Methods

### Method 1: Automated with Ansible (Recommended)

```bash
cd iaac/

# Deploy to sandbox environment
ansible-playbook -i ansible/inventory/sandbox.yml \
  ansible/playbooks/deploy-traefik.yml

# Deploy to production
ansible-playbook -i ansible/inventory/prod.yml \
  ansible/playbooks/deploy-traefik.yml
```

### Method 2: Manual Installation

#### 1. Install Traefik Binary

```bash
# SSH into EC2 instance
ssh ubuntu@<ec2-public-ip>

# Download and install Traefik
TRAEFIK_VERSION="3.0.0"
curl -L "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_amd64.tar.gz" -o /tmp/traefik.tar.gz
tar -xzf /tmp/traefik.tar.gz -C /tmp/
sudo mv /tmp/traefik /usr/local/bin/traefik
sudo chmod +x /usr/local/bin/traefik
rm /tmp/traefik.tar.gz
```

#### 2. Create Configuration Directories

```bash
sudo mkdir -p /etc/traefik/dynamic
sudo mkdir -p /var/log/traefik
sudo touch /etc/traefik/acme.json
sudo chmod 600 /etc/traefik/acme.json
```

#### 3. Create Traefik Static Configuration

Create `/etc/traefik/traefik.yml`:

```yaml
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
        # Cloudflare IP ranges
        - "173.245.48.0/20"
        - "103.21.244.0/22"
        # ... (add all Cloudflare IPs)

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
      email: "ops@paymentform.io"
      storage: /etc/traefik/acme.json
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 30

log:
  level: INFO
  format: json
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log
  format: json

ping:
  entryPoint: websecure
```

#### 4. Create Environment File for Cloudflare

Create `/etc/traefik/traefik.env`:

```bash
CF_API_EMAIL=ops@paymentform.io
CF_DNS_API_TOKEN=your_cloudflare_api_token_here
```

Set permissions:

```bash
sudo chmod 600 /etc/traefik/traefik.env
```

#### 5. Create Systemd Service

Create `/etc/systemd/system/traefik.service`:

```ini
[Unit]
Description=Traefik Reverse Proxy
After=network-online.target docker.service
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

[Install]
WantedBy=multi-user.target
```

#### 6. Start Traefik

```bash
sudo systemctl daemon-reload
sudo systemctl enable traefik
sudo systemctl start traefik
sudo systemctl status traefik
```

## Verification

### Check Traefik Status

```bash
sudo systemctl status traefik
sudo journalctl -u traefik -f
```

### Test Health Endpoint

```bash
curl -k https://localhost/ping
```

### Check Certificate Generation

```bash
sudo cat /etc/traefik/acme.json
```

### View Dashboard

Access Traefik dashboard at: `https://traefik.sandbox.paymentform.io`

Default credentials:
- Username: `admin`
- Password: (set via basic auth in dynamic config)

## Docker Integration

Traefik automatically discovers containers with proper labels. Example:

```yaml
services:
  backend:
    image: ghcr.io/paymentform/paymentform-backend:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.backend.rule=Host(`api.sandbox.paymentform.io`)"
      - "traefik.http.routers.backend.entrypoints=websecure"
      - "traefik.http.services.backend.loadbalancer.server.port=8000"
```

## Monitoring and Logs

### View Real-time Logs

```bash
# Traefik logs
sudo tail -f /var/log/traefik/traefik.log

# Access logs
sudo tail -f /var/log/traefik/access.log

# System logs
sudo journalctl -u traefik -f
```

### Log Rotation

Logrotate is configured automatically:

```bash
cat /etc/logrotate.d/traefik
```

## Troubleshooting

### Traefik Not Starting

```bash
# Check service status
sudo systemctl status traefik

# Check configuration
traefik --configFile=/etc/traefik/traefik.yml --dry-run

# Check logs
sudo journalctl -u traefik -n 50
```

### Certificate Issues

```bash
# Check acme.json permissions
ls -la /etc/traefik/acme.json

# Should be: -rw------- (600)

# Verify Cloudflare credentials
echo $CF_DNS_API_TOKEN
```

### Container Not Discovered

```bash
# Verify Docker socket access
ls -la /var/run/docker.sock

# Check container labels
docker inspect <container-name> | grep traefik

# Verify Traefik can see containers
docker logs traefik-container 2>&1 | grep -i "provider.docker"
```

### SSL Certificate Not Working

1. Verify DNS is pointing to correct IP
2. Check Cloudflare DNS is in "DNS Only" mode for ACME challenge
3. Wait 1-2 minutes for certificate generation
4. Check logs: `journalctl -u traefik | grep acme`

## Performance Tuning

### For High Traffic

Edit `/etc/traefik/traefik.yml`:

```yaml
# Increase connection limits
entryPoints:
  websecure:
    transport:
      respondingTimeouts:
        readTimeout: 60s
        writeTimeout: 60s
        idleTimeout: 180s
    
# Enable compression
http:
  middlewares:
    compression:
      compress: {}
```

Restart Traefik:

```bash
sudo systemctl restart traefik
```

## Security Best Practices

1. **Restrict Dashboard Access**: Use BasicAuth or IP whitelist
2. **Keep Updated**: Regularly update Traefik binary
3. **Monitor Logs**: Set up log aggregation (CloudWatch, ELK)
4. **Rotate Credentials**: Regularly rotate Cloudflare API tokens
5. **Use TLS 1.2+**: Configure minimum TLS version

## Next Steps

- [GitHub Registry Setup](./github-registry-setup.md)
- [Cloudflare Setup](./cloudflare-setup.md)
- [Complete Deployment](../SANDBOX-DEPLOY.md)
