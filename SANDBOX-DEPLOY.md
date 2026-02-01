# Sandbox Deployment - Step by Step

> **Goal**: Deploy Payment Form to sandbox.paymentform.io in under 30 minutes

## Prerequisites Check

```bash
# Verify tools installed
command -v tofu >/dev/null 2>&1 || echo "❌ Install OpenTofu: https://opentofu.org/docs/intro/install/"
command -v aws >/dev/null 2>&1 || echo "❌ Install AWS CLI: https://aws.amazon.com/cli/"
command -v make >/dev/null 2>&1 || echo "⚠️  make not found (optional)"

# Verify AWS credentials
aws sts get-caller-identity || echo "❌ Configure AWS: aws configure"
```

## Step 1: Get API Credentials

```bash
# 1.1 - Get Neon API Key
# Visit: https://console.neon.tech/app/settings/api-keys
# Copy the API key

# 1.2 - Get Turso API Token
turso auth login
turso auth token
# Copy the token

# 1.3 - Get Turso Organization Slug
turso org show
# Copy the organization slug
```

## Step 2: Store Secrets in AWS

```bash
# 2.1 - Store Neon API key
aws secretsmanager create-secret \
  --name neon-api-key \
  --secret-string "YOUR_NEON_API_KEY_HERE" \
  --region us-east-1

# 2.2 - Store Turso API token
aws secretsmanager create-secret \
  --name turso-api-token \
  --secret-string "YOUR_TURSO_TOKEN_HERE" \
  --region us-east-1

# Verify secrets stored
aws secretsmanager list-secrets --region us-east-1 | grep -E "(neon|turso)"
```

## Step 3: Export Credentials for Terraform

```bash
# 3.1 - Export Neon API key
export TF_VAR_neon_api_key=$(aws secretsmanager get-secret-value \
  --secret-id neon-api-key \
  --query SecretString \
  --output text \
  --region us-east-1)

# 3.2 - Export Turso API token
export TF_VAR_turso_api_token=$(aws secretsmanager get-secret-value \
  --secret-id turso-api-token \
  --query SecretString \
  --output text \
  --region us-east-1)

# 3.3 - Verify exports
echo "Neon key: ${TF_VAR_neon_api_key:0:20}..."
echo "Turso token: ${TF_VAR_turso_api_token:0:20}..."
```

## Step 4: Create Terraform State Backend

```bash
# 4.1 - Create S3 bucket for state
aws s3 mb s3://paymentform-terraform-state-sandbox --region us-east-1

# 4.2 - Enable versioning
aws s3api put-bucket-versioning \
  --bucket paymentform-terraform-state-sandbox \
  --versioning-configuration Status=Enabled

# 4.3 - Enable encryption
aws s3api put-bucket-encryption \
  --bucket paymentform-terraform-state-sandbox \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# 4.4 - Create DynamoDB table for state locking (if not exists)
aws dynamodb create-table \
  --table-name paymentform-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1 \
  || echo "✓ Lock table already exists"
```

## Step 5: Initialize Infrastructure

```bash
# 5.1 - Navigate to iaac directory
cd /path/to/paymentform-docker/iaac

# 5.2 - Initialize with sandbox backend
make init ENV=sandbox

# OR manually:
tofu init -backend-config=infrastructure/environments/sandbox/backend.hcl
```

## Step 6: Review Configuration

```bash
# 6.1 - Check sandbox variables
cat infrastructure/environments/sandbox/terraform.tfvars

# Should show:
# environment  = "sandbox"
# domain_name  = "sandbox.paymentform.io"
# api_subdomain = "api.sandbox.paymentform.io"
# app_subdomain = "app.sandbox.paymentform.io"
# renderer_subdomain = "*.sandbox.paymentform.io"

# 6.2 - Edit if needed
vim infrastructure/environments/sandbox/terraform.tfvars
```

## Step 7: Plan Deployment

```bash
# 7.1 - Generate execution plan
make plan ENV=sandbox

# OR manually:
tofu plan \
  -var-file=infrastructure/environments/sandbox/terraform.tfvars \
  -out=tfplan-sandbox

# 7.2 - Review the plan output
# Look for:
# - Resources to be created
# - No unexpected deletions
# - Cost estimates (if using Infracost)
```

## Step 8: Deploy Infrastructure

```bash
# 8.1 - Apply the plan
make apply ENV=sandbox

# OR manually:
tofu apply tfplan-sandbox

# 8.2 - Confirm when prompted
# Type: yes

# ⏱️  This takes 10-15 minutes
# ☕ Time for coffee!
```

## Step 9: Get Infrastructure Outputs

```bash
# 9.1 - Show all outputs
make output ENV=sandbox

# OR manually:
tofu output -json > sandbox-outputs.json
cat sandbox-outputs.json | jq '.'

# 9.2 - Key outputs to note:
# - ALB DNS name (for api.sandbox.paymentform.io)
# - CloudFront distributions (for app and renderer)
# - Database connection strings
```

## Step 10: Configure DNS Records

```bash
# 10.1 - Get Route53 hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='sandbox.paymentform.io.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"

# 10.2 - If you manage DNS externally (e.g., Cloudflare):
# Get the outputs and create these records:

# A    api.sandbox.paymentform.io     → <ALB_DNS_NAME>
# CNAME app.sandbox.paymentform.io   → <CLOUDFRONT_CLIENT_DOMAIN>
# CNAME *.sandbox.paymentform.io     → <CLOUDFRONT_RENDERER_DOMAIN>

# Values from:
tofu output alb_dns_name
tofu output cloudfront_client_domain
tofu output cloudfront_renderer_domain
```

## Step 11: Request SSL Certificate

```bash
# 11.1 - Request certificate (must be in us-east-1 for CloudFront)
aws acm request-certificate \
  --domain-name "sandbox.paymentform.io" \
  --subject-alternative-names \
    "*.sandbox.paymentform.io" \
    "api.sandbox.paymentform.io" \
    "app.sandbox.paymentform.io" \
  --validation-method DNS \
  --region us-east-1

# 11.2 - Get certificate ARN
CERT_ARN=$(aws acm list-certificates \
  --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='sandbox.paymentform.io'].CertificateArn" \
  --output text)

echo "Certificate ARN: $CERT_ARN"

# 11.3 - Get DNS validation records
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions[*].[DomainName,ResourceRecord.Name,ResourceRecord.Value]" \
  --output table

# 11.4 - Add CNAME records to your DNS for validation
# Wait for validation (can take 5-30 minutes)

# 11.5 - Check validation status
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query "Certificate.Status" \
  --output text
```

## Step 12: Build and Push Docker Images

```bash
# 12.1 - Authenticate to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 12.2 - Build backend image
cd ../backend
docker build -t ghcr.io/YOUR_ORG/paymentform-backend:sandbox .

# 12.3 - Build client image
cd ../client
docker build -t ghcr.io/YOUR_ORG/paymentform-client:sandbox .

# 12.4 - Build renderer image
cd ../renderer
docker build -t ghcr.io/YOUR_ORG/paymentform-renderer:sandbox .

# 12.5 - Push images
docker push ghcr.io/YOUR_ORG/paymentform-backend:sandbox
docker push ghcr.io/YOUR_ORG/paymentform-client:sandbox
docker push ghcr.io/YOUR_ORG/paymentform-renderer:sandbox
```

## Step 13: Deploy Application with Ansible

```bash
# 13.1 - Navigate back to iaac
cd ../iaac

# 13.2 - Update Ansible inventory with server IPs
# Get ECS cluster info from outputs
vim ansible/inventory/sandbox

# 13.3 - Deploy backend
ansible-playbook \
  -i ansible/inventory/sandbox \
  ansible/playbooks/deploy-backend.yml

# 13.4 - Deploy client
ansible-playbook \
  -i ansible/inventory/sandbox \
  ansible/playbooks/deploy-client.yml

# 13.5 - Deploy renderer
ansible-playbook \
  -i ansible/inventory/sandbox \
  ansible/playbooks/deploy-renderer.yml
```

## Step 14: Verify Deployment

```bash
# 14.1 - Check backend health
curl https://api.sandbox.paymentform.io/health
# Expected: {"status": "ok"}

# 14.2 - Check client
curl -I https://app.sandbox.paymentform.io
# Expected: HTTP/2 200

# 14.3 - Check renderer (test tenant)
curl -I https://test-tenant.sandbox.paymentform.io
# Expected: HTTP/2 200

# 14.4 - Check CloudFront distribution status
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?contains(@, 'sandbox.paymentform.io')]].{Id:Id,Status:Status,Domain:DomainName}" \
  --output table
```

## Step 15: Configure Application

```bash
# 15.1 - SSH to backend instance (via Session Manager)
aws ssm start-session --target <INSTANCE_ID>

# 15.2 - Run database migrations
cd /var/www/html
php artisan migrate --force

# 15.3 - Seed initial data (optional)
php artisan db:seed --force

# 15.4 - Create admin user
php artisan user:create admin@paymentform.io --admin

# 15.5 - Verify app key is set
php artisan key:generate --show
```

## Step 16: Final Checks

```bash
# 16.1 - Visit the application
open https://app.sandbox.paymentform.io

# 16.2 - Login with admin credentials

# 16.3 - Create a test tenant
# Navigate to: Tenants → Create New Tenant

# 16.4 - Verify tenant subdomain works
open https://test-tenant.sandbox.paymentform.io

# 16.5 - Check CloudWatch logs
aws logs tail /aws/ecs/paymentform-sandbox --follow

# 16.6 - Check metrics
# Visit AWS Console → CloudWatch → Dashboards
```

## Troubleshooting

### Issue: `tofu init` fails

```bash
# Check backend configuration
cat infrastructure/environments/sandbox/backend.hcl

# Verify S3 bucket exists
aws s3 ls s3://paymentform-terraform-state-sandbox

# Verify DynamoDB table exists
aws dynamodb describe-table --table-name paymentform-terraform-lock
```

### Issue: Certificate validation pending

```bash
# Check DNS records are added correctly
dig CNAME _xxx.sandbox.paymentform.io

# Force DNS propagation check
aws acm describe-certificate --certificate-arn $CERT_ARN
```

### Issue: Health check fails

```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>

# Check ECS tasks
aws ecs list-tasks --cluster paymentform-sandbox
aws ecs describe-tasks --cluster paymentform-sandbox --tasks <TASK_ARN>

# Check logs
aws logs tail /aws/ecs/paymentform-sandbox-backend --since 10m
```

### Issue: CloudFront not serving content

```bash
# Check origin configuration
aws cloudfront get-distribution --id <DISTRIBUTION_ID>

# Create cache invalidation
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*"

# Wait for invalidation
aws cloudfront wait invalidation-completed \
  --distribution-id <DISTRIBUTION_ID> \
  --id <INVALIDATION_ID>
```

## Rollback Procedure

If something goes wrong:

```bash
# 1. Destroy infrastructure
make destroy ENV=sandbox
# Type: yes when prompted

# 2. Or revert to previous state
aws s3 ls s3://paymentform-terraform-state-sandbox/sandbox/

# 3. Download previous state version
aws s3api list-object-versions \
  --bucket paymentform-terraform-state-sandbox \
  --prefix sandbox/terraform.tfstate

# 4. Restore previous version
aws s3api get-object \
  --bucket paymentform-terraform-state-sandbox \
  --key sandbox/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup

# 5. Re-apply previous state
mv terraform.tfstate.backup terraform.tfstate
tofu apply
```

## Cleanup (When Done Testing)

```bash
# Destroy all sandbox resources
cd /path/to/paymentform-docker/iaac
make destroy ENV=sandbox
# Type: yes when prompted

# Remove Docker images
docker rmi ghcr.io/YOUR_ORG/paymentform-backend:sandbox
docker rmi ghcr.io/YOUR_ORG/paymentform-client:sandbox
docker rmi ghcr.io/YOUR_ORG/paymentform-renderer:sandbox

# Keep state bucket for history (optional cleanup)
# aws s3 rb s3://paymentform-terraform-state-sandbox --force
```

## Summary Checklist

- [ ] AWS credentials configured
- [ ] Neon API key obtained and stored
- [ ] Turso API token obtained and stored
- [ ] S3 state bucket created
- [ ] DynamoDB lock table created
- [ ] Infrastructure initialized (`make init`)
- [ ] Plan reviewed (`make plan`)
- [ ] Infrastructure deployed (`make apply`)
- [ ] DNS records configured
- [ ] SSL certificate requested and validated
- [ ] Docker images built and pushed
- [ ] Applications deployed with Ansible
- [ ] Database migrations run
- [ ] Health checks passing
- [ ] All subdomains accessible

## Estimated Time

- Prerequisites: 10 minutes
- Steps 1-8 (Infrastructure): 20-30 minutes
- Steps 9-11 (DNS/SSL): 15-45 minutes (depends on validation time)
- Steps 12-16 (Application): 15-20 minutes

**Total**: 60-105 minutes first time, 30-45 minutes subsequent deploys

## Next Steps

After successful deployment:

1. **Monitor**: Check CloudWatch dashboards
2. **Test**: Run integration tests
3. **Document**: Update runbook with any changes
4. **Security**: Run security audit
5. **Performance**: Load test the API
6. **Backup**: Verify backup schedules
7. **Alerts**: Configure alerting

---

**Questions?** Check `AGENT.md` or `docs/deployment-guide.md` for more details.
