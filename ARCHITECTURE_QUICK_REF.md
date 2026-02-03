# Quick Reference: Refactored Architecture

## ❌ Removed
- **ALB**: Traefik on EC2 replaces it
- **AWS Secrets Manager**: Use bash `TF_VAR_*` variables instead

## ✅ Kept
- **VPC**: Network isolation (required even with Cloudflare)
- **EC2 ASG**: Traefik + Backend (direct Cloudflare traffic)
- **Neon DB**: Central PostgreSQL
- **Turso DB**: Tenant databases
- **Amplify**: Client + Renderer hosting
- **Cloudflare**: DNS + TLS + edge LB

## Traffic Flow
```
User → Cloudflare → EC2 (Traefik) → Backend/Services
```

## Environment Variables Only
```bash
export TF_VAR_neon_api_key="neon_xxx"
export TF_VAR_turso_api_token="tsoc_xxx"
export TF_VAR_cloudflare_api_token="xxx"
export TF_VAR_cloudflare_zone_id="xxx"
export TF_VAR_amplify_access_token="ghp_xxx"
export TF_VAR_environment="sandbox"
```

## Deploy Command
```bash
cd /mnt/src/work/apps/paymentform-docker/iaac
rm -f tfplan-* .terraform.lock.hcl
tofu init -backend-config=infrastructure/environments/sandbox/backend.hcl
tofu plan -var-file=infrastructure/environments/sandbox/terraform.tfvars -out=tfplan-sandbox
tofu apply tfplan-sandbox
```

## Instance IPs Output
```bash
tofu output instance_ips
# Use these IPs for Ansible configuration
```

## Files Changed
- `infrastructure/main.tf` - Removed ALB module, updated Cloudflare module
- `infrastructure/variables.tf` - Removed ALB variables, Secrets Manager refs
- `infrastructure/modules/compute/main.tf` - Added instance IP data source
- `infrastructure/modules/compute/outputs.tf` - Added `instance_ips` output
- `infrastructure/modules/security/main.tf` - Renamed ALB SG to EC2 SG, removed ALB rules
- `infrastructure/modules/security/outputs.tf` - Removed `alb_security_group_id` output
