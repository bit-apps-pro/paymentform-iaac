# Cloudflare Setup Guide

This guide walks through setting up Cloudflare for DNS management, load balancing, and security features.

## Prerequisites

- Cloudflare account
- Domain `paymentform.io` added to Cloudflare
- Cloudflare API token with Zone:Edit and Load Balancer:Edit permissions
- AWS infrastructure deployed (EC2 instances)

## Step 1: Get Cloudflare Credentials

### 1.1 Get Zone ID

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain `paymentform.io`
3. Scroll down to find **Zone ID** on the right sidebar
4. Copy the Zone ID

### 1.2 Create API Token

1. Go to Profile → API Tokens
2. Click "Create Token"
3. Use the "Edit zone DNS" template or create custom token with:
   - Permissions:
     - Zone → DNS → Edit
     - Zone → Load Balancers → Edit
     - Zone → Zone Settings → Edit
     - Zone → WAF → Edit
   - Zone Resources:
     - Include → Specific zone → `paymentform.io`
4. Create Token and copy it securely

## Step 2: Store Secrets in AWS

```bash
# Store Cloudflare API token
aws secretsmanager create-secret \
  --name cloudflare-api-token \
  --secret-string "YOUR_CLOUDFLARE_API_TOKEN" \
  --region us-east-1

# Store Cloudflare Zone ID
aws secretsmanager create-secret \
  --name cloudflare-zone-id \
  --secret-string "YOUR_CLOUDFLARE_ZONE_ID" \
  --region us-east-1

# Verify
aws secretsmanager list-secrets --region us-east-1 | grep cloudflare
```

## Step 3: Export Terraform Variables

```bash
# Export Cloudflare credentials
export TF_VAR_cloudflare_api_token=$(aws secretsmanager get-secret-value \
  --secret-id cloudflare-api-token \
  --query SecretString \
  --output text \
  --region us-east-1)

export TF_VAR_cloudflare_zone_id=$(aws secretsmanager get-secret-value \
  --secret-id cloudflare-zone-id \
  --query SecretString \
  --output text \
  --region us-east-1)

# Verify
echo "CF Token: ${TF_VAR_cloudflare_api_token:0:20}..."
echo "Zone ID: ${TF_VAR_cloudflare_zone_id}"
```

## Step 4: Deploy Infrastructure

After deploying AWS infrastructure with Terraform/OpenTofu, get the EC2 instance public IPs:

```bash
# Get EC2 instance IPs
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=sandbox" \
  --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

## Step 5: Update Terraform with Origin IPs

Edit `infrastructure/environments/sandbox.tfvars`:

```hcl
# Origin IPs from EC2 instances
api_origin_ips     = ["1.2.3.4", "5.6.7.8"]
app_origin_ips     = ["1.2.3.4", "5.6.7.8"]
renderer_origin_ip = "1.2.3.4"
```

Then apply:

```bash
cd iaac/
make apply ENV=sandbox
```

## Step 6: Verify Cloudflare Configuration

### Check DNS Records

```bash
dig api.sandbox.paymentform.io
dig app.sandbox.paymentform.io
dig tenant1.sandbox.paymentform.io
```

### Check Load Balancer

1. Go to Cloudflare Dashboard → Traffic → Load Balancing
2. Verify pools are created with correct origins
3. Check health monitors are running
4. Verify all origins show as "Healthy"

### Test Security Features

```bash
# Test HTTPS redirect
curl -I http://api.sandbox.paymentform.io

# Test SSL/TLS
curl -vI https://api.sandbox.paymentform.io

# Test rate limiting (should get 429 after threshold)
for i in {1..150}; do curl https://api.sandbox.paymentform.io/health; done
```

## Step 7: Configure Production

For production, repeat the same steps with production values:

```hcl
# infrastructure/environments/prod.tfvars
api_subdomain      = "api.paymentform.io"
app_subdomain      = "app.paymentform.io"
renderer_subdomain = "*.paymentform.io"

api_origin_ips     = ["1.2.3.4", "5.6.7.8", "9.10.11.12"]  # 3 regions
app_origin_ips     = ["1.2.3.4", "5.6.7.8", "9.10.11.12"]
renderer_origin_ip = "1.2.3.4"
```

## Troubleshooting

### DNS Not Resolving

- Verify Zone ID is correct
- Check Cloudflare nameservers are configured at domain registrar
- Wait up to 5 minutes for DNS propagation

### Load Balancer Shows Origins as Unhealthy

- Check EC2 security groups allow Cloudflare IPs
- Verify Traefik is running: `systemctl status traefik`
- Check health endpoint returns 200: `curl localhost/health`
- Review health monitor settings in Cloudflare

### SSL Certificate Issues

- Verify Cloudflare API token has correct permissions
- Check `/etc/traefik/acme.json` exists with 600 permissions
- Review Traefik logs: `journalctl -u traefik -f`
- Ensure DNS records are proxied (orange cloud)

### Rate Limiting Not Working

- Verify WAF is enabled in terraform: `enable_rate_limiting = true`
- Check Cloudflare dashboard → Security → WAF
- Review rate limiting rules

## Cost Breakdown

- **Cloudflare Load Balancer**: $5/month
- **Additional origins**: Free (up to 2 included, $5/month each after)
- **Additional health checks**: Free (up to 2 included, $5/month each after)
- **WAF/DDoS**: Free (included in all plans)
- **Rate Limiting**: Free (up to 10 rules)

## Next Steps

- [Traefik Cloud Setup](./traefik-cloud-setup.md)
- [GitHub Registry Setup](./github-registry-setup.md)
- [Sandbox Deployment Guide](../SANDBOX-DEPLOY.md)
