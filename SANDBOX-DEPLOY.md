# Sandbox Deployment

> **Stack**: Cloudflare + Traefik + EC2 + S3 + Amplify + Turso + Neon  
> **Domains**: sandbox.paymentform.io (api, app, *)

## Prerequisites

```bash
# Verify tools
command -v tofu aws make

# AWS credentials
aws sts get-caller-identity
```

## Architecture

```
Cloudflare → Load Balancer
   ├─→ api.sandbox.paymentform.io  → EC2 (Traefik + Backend)
   ├─→ app.sandbox.paymentform.io  → AWS Amplify (Client)
   └─→ *.sandbox.paymentform.io    → AWS Amplify (Renderer)

Backend: Ansible-managed Docker on EC2 (Ubuntu)
Frontend: AWS Amplify (automated from Git)
```

## Step 1: Get Credentials

```bash
# Neon API Key
# https://console.neon.tech/app/settings/api-keys

# Turso API Token
turso auth login && turso auth token

# Cloudflare API Token
# https://dash.cloudflare.com/profile/api-tokens
# Permissions: Zone:DNS:Edit, Zone:SSL:Edit

# Cloudflare Zone ID
# https://dash.cloudflare.com → paymentform.io → Overview

# GitHub Token (for Amplify private repos)
# https://github.com/settings/tokens/new
# Scope: repo
```

## Step 2: Export Credentials

```bash
export TF_VAR_neon_api_key="neon_xxx"
export TF_VAR_turso_api_token="tsoc_xxx"
export TF_VAR_cloudflare_api_token="xxx"
export TF_VAR_cloudflare_zone_id="xxx"
export TF_VAR_amplify_access_token="ghp_xxx"
```

## Step 3: Terraform State Backend

```bash
# S3 bucket
aws s3 mb s3://paymentform-terraform-state-sandbox --region us-east-1
aws s3api put-bucket-versioning \
  --bucket paymentform-terraform-state-sandbox \
  --versioning-configuration Status=Enabled

# DynamoDB lock table
aws dynamodb create-table \
  --table-name paymentform-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Step 4: Configure Infrastructure

```bash
cd /path/to/paymentform-docker/iaac

# Edit terraform.tfvars
cat > terraform.tfvars <<EOF
environment = "sandbox"
region      = "us-east-1"

# Domains
api_subdomain      = "api.sandbox.paymentform.io"
app_subdomain      = "app.sandbox.paymentform.io"
renderer_subdomain = "*.sandbox.paymentform.io"

# Cloudflare (automatic DNS + SSL)
cloudflare_zone_id = "\${TF_VAR_cloudflare_zone_id}"

# Amplify
enable_amplify              = true
renderer_repository_url     = "https://github.com/your-org/renderer"
renderer_branch_name        = "main"
client_repository_url       = "https://github.com/your-org/client"
client_branch_name          = "main"

# Databases
neon_api_key    = "\${TF_VAR_neon_api_key}"
turso_api_token = "\${TF_VAR_turso_api_token}"

# EC2
instance_type    = "t3.medium"
desired_capacity = 2
min_size         = 1
max_size         = 4

# S3
enable_versioning = true
EOF
```

## Step 5: Deploy Infrastructure

# Initialize
```bash
make init ENV=sandbox
-- 
tofu init -backend-config=infrastructure/environments/sandbox/backend.hcl
```
# Plan
```bash
make plan ENV=sandbox
--
tofu plan \
  -var-file=infrastructure/environments/sandbox/terraform.tfvars \
  -out=tfplan-sandbox
```
# Apply
```bash
make apply ENV=sandbox
--
tofu apply tfplan-sandbox
```

**Deploys**:
- VPC + Subnets + NAT Gateway
- EC2 Auto Scaling Group (Ubuntu 22.04 LTS)
- S3 Buckets
- Neon PostgreSQL Database
- Turso SQLite Databases (tenant, analytics, backup)
- Cloudflare DNS Records (api, app, * subdomains)
- Cloudflare SSL/TLS (Full Strict mode)
- AWS Amplify Apps (client + renderer - managed separately)

## Step 6: Configure Ansible Inventory

```bash
# Get EC2 IP from Terraform
EC2_IP=$(tofu output -raw ec2_public_ip)

# Update Ansible inventory
cat > ansible/inventory/sandbox <<EOF
[backend]
backend-1 ansible_host=${EC2_IP}

[backend:vars]
environment=sandbox
aws_region=us-east-1
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/paymentform.pem
EOF
```

## Step 7: Export Terraform Outputs for Ansible

```bash
# Export database connection strings
export TF_OUTPUT_NEON_CONNECTION_STRING=$(tofu output -raw neon_connection_string)
export TF_OUTPUT_TURSO_TENANT_URL=$(tofu output -raw turso_tenant_url)
export TF_OUTPUT_TURSO_ANALYTICS_URL=$(tofu output -raw turso_analytics_url)

# Export domain configuration
export TF_OUTPUT_API_SUBDOMAIN=$(tofu output -raw api_subdomain)
export TF_OUTPUT_APP_SUBDOMAIN=$(tofu output -raw app_subdomain)
export TF_OUTPUT_RENDERER_SUBDOMAIN=$(tofu output -raw renderer_subdomain)

# Export ECR registry (if using)
export TF_OUTPUT_ECR_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 8: Deploy Backend with Ansible

```bash
cd ansible

# Test connectivity
ansible -i inventory/sandbox backend -m ping

# Deploy backend service (includes Docker installation)
ansible-playbook -i inventory/sandbox playbooks/deploy-backend.yml

# Deploy Traefik reverse proxy (optional)
ansible-playbook -i inventory/sandbox playbooks/deploy-traefik.yml
```

## Step 9: Verify Deployment

```bash
# Check Cloudflare DNS
curl -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" | \
  jq '.result[] | select(.name | contains("sandbox")) | "\(.name) → \(.content)"'

# Check SSL
curl -I https://api.sandbox.paymentform.io
curl -I https://app.sandbox.paymentform.io

# Check Amplify builds
aws amplify list-apps
aws amplify list-jobs --app-id $(tofu output -raw renderer_app_id) --branch-name main

# Check databases
psql $(tofu output -raw neon_connection_string) -c "SELECT version();"
turso db show $(tofu output -raw tenant_db_name)

# Test API
curl https://api.sandbox.paymentform.io/health
```

## Step 9: Monitor

```bash
# EC2 instances
aws ec2 describe-instances --filters "Name=tag:Environment,Values=sandbox"

# Traefik dashboard
ssh -L 8080:localhost:8080 ec2-user@$EC2_IP
# Visit: http://localhost:8080/dashboard/

# Cloudflare Analytics
# https://dash.cloudflare.com/zones/${CLOUDFLARE_ZONE_ID}/analytics

# Amplify build logs
# https://console.aws.amazon.com/amplify/

# Neon dashboard
# https://console.neon.tech/

# Turso dashboard
# https://turso.tech/app
```

## Architecture

```
Internet
   ↓
Cloudflare (DNS + CDN + SSL + WAF)
   ├─→ api.sandbox.paymentform.io → EC2 (Traefik + Backend)
   ├─→ app.sandbox.paymentform.io → Amplify (Client)
   └─→ *.sandbox.paymentform.io   → Amplify (Renderer)
   
Backend (EC2)
   ├─→ Neon PostgreSQL (Main DB)
   └─→ Turso SQLite (Tenant/Analytics/Backup)

Static Assets
   └─→ S3 Buckets
```

## Outputs

```bash
tofu output
```

Key outputs:
- `renderer_branch_url`: Amplify renderer URL
- `client_branch_url`: Amplify client URL
- `neon_connection_string`: PostgreSQL connection
- `tenant_db_url`: Turso tenant database
- `analytics_db_url`: Turso analytics database

## Troubleshooting

```bash
# DNS not resolving
nslookup api.sandbox.paymentform.io

# SSL certificate issues
curl -v https://api.sandbox.paymentform.io

# Backend not responding
ssh ec2-user@$EC2_IP "docker-compose logs -f backend"

# Amplify build failed
aws amplify get-job --app-id <app-id> --branch-name main --job-id <job-id>

# Database connection issues
psql $(tofu output -raw neon_connection_string)
turso db shell $(tofu output -raw tenant_db_name)
```

## Clean Up

```bash
# Destroy infrastructure
tofu destroy

# Delete S3 state
aws s3 rb s3://paymentform-terraform-state-sandbox --force

# Delete DynamoDB table
aws dynamodb delete-table --table-name paymentform-terraform-lock
```

## Time Estimate

- Setup: 5 min
- Deploy: 15 min
- Verify: 5 min
- **Total**: ~25 minutes
