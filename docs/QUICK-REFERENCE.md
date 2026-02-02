# Quick Reference: Cloudflare + Traefik + GHCR

## One-Page Deployment Guide

### 1. Get Credentials (5 min)

```bash
# Cloudflare
# Visit: https://dash.cloudflare.com
# Get: Zone ID + API Token (Zone:Edit, LB:Edit)

# GitHub
# Visit: https://github.com/settings/tokens
# Create: PAT with read:packages scope
```

### 2. Store in AWS Secrets (2 min)

```bash
aws secretsmanager create-secret --name cloudflare-api-token --secret-string "YOUR_TOKEN"
aws secretsmanager create-secret --name cloudflare-zone-id --secret-string "YOUR_ZONE_ID"
aws secretsmanager create-secret --name github-ghcr-token --secret-string "ghp_YOUR_TOKEN"
```

### 3. Deploy Infrastructure (10 min)

```bash
cd iaac/

# Export credentials
export TF_VAR_cloudflare_api_token=$(aws secretsmanager get-secret-value --secret-id cloudflare-api-token --query SecretString --output text)
export TF_VAR_cloudflare_zone_id=$(aws secretsmanager get-secret-value --secret-id cloudflare-zone-id --query SecretString --output text)
export TF_VAR_neon_api_key=$(aws secretsmanager get-secret-value --secret-id neon-api-key --query SecretString --output text)
export TF_VAR_turso_api_token=$(aws secretsmanager get-secret-value --secret-id turso-api-token --query SecretString --output text)

# Deploy
make init ENV=sandbox
make plan ENV=sandbox
make apply ENV=sandbox
```

### 4. Update Origin IPs (2 min)

```bash
# Get EC2 IPs
aws ec2 describe-instances --filters "Name=tag:Environment,Values=sandbox" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' --output text

# Edit infrastructure/environments/sandbox.tfvars
# Update: api_origin_ips, app_origin_ips, renderer_origin_ip

# Apply
make apply ENV=sandbox
```

### 5. Verify (3 min)

```bash
# DNS
dig api.sandbox.paymentform.io

# HTTPS
curl https://api.sandbox.paymentform.io/health

# Traefik
systemctl status traefik
```

## Environment Variables Cheat Sheet

### For Terraform

```bash
export TF_VAR_cloudflare_api_token="cf_token_here"
export TF_VAR_cloudflare_zone_id="zone_id_here"
export TF_VAR_neon_api_key="neon_key_here"
export TF_VAR_turso_api_token="turso_token_here"
```

### For Docker Compose

```bash
# .env
GITHUB_REPOSITORY_OWNER=your-org
IMAGE_TAG=latest
TRAEFIK_HOST=sandbox.paymentform.io
```

## Common Commands

### Terraform

```bash
make init ENV=sandbox          # Initialize
make plan ENV=sandbox          # Plan changes
make apply ENV=sandbox         # Apply changes
make destroy ENV=sandbox       # Destroy (careful!)
```

### Traefik

```bash
sudo systemctl status traefik        # Check status
sudo systemctl restart traefik       # Restart
sudo journalctl -u traefik -f        # View logs
sudo tail -f /var/log/traefik/access.log  # Access logs
```

### Docker

```bash
docker-compose up -d              # Start all services
docker-compose ps                 # List services
docker-compose logs -f backend    # View logs
docker-compose pull               # Pull latest images
```

### GHCR

```bash
# Login
echo $GHCR_TOKEN | docker login ghcr.io -u username --password-stdin

# Pull
docker pull ghcr.io/org/paymentform-backend:latest

# Push
docker push ghcr.io/org/paymentform-backend:latest
```

## URLs

### Sandbox

- API: https://api.sandbox.paymentform.io
- App: https://app.sandbox.paymentform.io
- Traefik: https://traefik.sandbox.paymentform.io
- Renderer: https://tenant1.sandbox.paymentform.io

### Production

- API: https://api.paymentform.io
- App: https://app.paymentform.io
- Traefik: https://traefik.paymentform.io
- Renderer: https://tenant1.paymentform.io

## Troubleshooting Quick Fixes

### DNS Not Resolving

```bash
# Check nameservers
dig paymentform.io NS

# Wait 5 minutes for propagation
# Verify in Cloudflare dashboard
```

### Traefik Not Starting

```bash
sudo systemctl status traefik
sudo journalctl -u traefik -n 50
traefik --configFile=/etc/traefik/traefik.yml --dry-run
```

### Certificate Issues

```bash
sudo ls -la /etc/traefik/acme.json  # Should be 600
sudo cat /etc/traefik/acme.json     # Check if populated
sudo journalctl -u traefik | grep acme
```

### Image Pull Failed

```bash
# Re-login
echo $GHCR_TOKEN | docker login ghcr.io -u username --password-stdin

# Check permissions
gh auth status

# Make image public (if needed)
# GitHub → Packages → Settings → Change visibility
```

## File Locations

### Configuration

- Terraform: `iaac/infrastructure/environments/*.tfvars`
- Traefik: `/etc/traefik/traefik.yml`
- Docker Compose: `docker-compose.yml`
- Environment: `.env`

### Logs

- Traefik: `/var/log/traefik/*.log`
- System: `journalctl -u traefik`
- Docker: `docker-compose logs`

### Secrets

- AWS Secrets Manager
- Cloudflare Dashboard
- GitHub Settings

## Cost Breakdown

| Item | Sandbox | Production | Savings |
|------|---------|------------|---------|
| ALB (old) | $16-32/mo | $48-96/mo | - |
| Cloudflare LB | $5/mo | $5/mo | $11-27/mo |
| GHCR | Free | ~$5-10/mo | - |
| **Total Savings** | | | **$43-91/mo** |

## Health Checks

```bash
# All-in-one check
curl -s https://api.sandbox.paymentform.io/health && echo "✓ API OK"
curl -s https://app.sandbox.paymentform.io && echo "✓ App OK"
systemctl is-active traefik && echo "✓ Traefik OK"
docker ps | grep -E "backend|client|renderer" && echo "✓ Containers OK"
```

## Contacts

- DevOps: ops@paymentform.io
- Documentation: `iaac/docs/`
- Issues: GitHub Issues

## Links

- [Full Documentation](./IMPLEMENTATION-SUMMARY.md)
- [Cloudflare Setup](./cloudflare-setup.md)
- [Traefik Setup](./traefik-cloud-setup.md)
- [GHCR Setup](./github-registry-setup.md)
