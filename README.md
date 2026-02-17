# Infrastructure as Code - PaymentForm

OpenTofu/Terraform infrastructure for PaymentForm application with AWS SSM secrets management and self-managed Turso databases.

## Quick Start

```bash
# 1. Set environment variables
cp .envrc.example .envrc
# Edit .envrc with your secrets
source .envrc

# 2. Deploy infrastructure
cd /mnt/src/work/apps/paymentform-docker/iaac
tofu init
tofu plan -out=tfplan
tofu apply tfplan
```

## Structure

```
iaac/
├── infrastructure/          # Main infrastructure modules
│   ├── modules/
│   │   ├── ssm/            # SSM Parameter Store (16 secrets)
│   │   ├── turso-self-managed/  # Turso CLI-based provisioning
│   │   ├── compute/        # EC2 instances + IAM
│   │   ├── networking/     # VPC, subnets, gateways
│   │   ├── security/       # Security groups
│   │   ├── storage/        # S3 buckets
│   │   ├── neon/           # Neon PostgreSQL (central DB)
│   │   └── cloudflare/     # DNS + KV namespaces
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── environments/            # Environment-specific configs
├── ansible/                 # Configuration management
└── scripts/                 # Deployment utilities
```

## Key Features

### SSM Secrets Management
- 16 backend secrets stored as SecureString (KMS encrypted)
- IAM least-privilege access for EC2
- Path: `/app/${environment}/backend/{KEY_NAME}`
- See: [SSM_SECRETS_GUIDE.md](./SSM_SECRETS_GUIDE.md)

### Turso Self-Managed
- CLI-based provisioning (no provider)
- 3 databases: tenants, analytics, backup
- Credentials stored in SSM
- See: [TURSO_GUIDE.md](./TURSO_GUIDE.md)

### Neon PostgreSQL
- Central database (unchanged)
- Handles DB_PASSWORD rotation only
- Module: `infrastructure/modules/neon/`

## Deployment

### Prerequisites
- OpenTofu/Terraform >= 1.5
- AWS CLI configured
- Turso CLI installed
- jq (optional)

### Environment Variables
All secrets must be set as `TF_VAR_*` environment variables. See `.envrc.example` for complete list.

Required:
- `TF_VAR_neon_api_key`
- `TF_VAR_turso_api_token`
- `TF_VAR_turso_auth_token`
- `TF_VAR_cloudflare_api_token`
- 16 backend secrets (app_key, db_password, redis_password, etc.)

### Deploy
```bash
tofu init
tofu plan
tofu apply
```

## Security

- ✅ All secrets marked sensitive
- ✅ KMS encryption (SecureString)
- ✅ IAM least-privilege
- ✅ No secrets in outputs/state
- ✅ CloudTrail audit logging

## Documentation

- **[SSM_SECRETS_GUIDE.md](./SSM_SECRETS_GUIDE.md)** - SSM Parameter Store setup & usage
- **[TURSO_GUIDE.md](./TURSO_GUIDE.md)** - Turso self-managed deployment
- `.envrc.example` - Environment variable template
- `terraform.tfvars.example` - Terraform variables example

## Cost Estimate

- **EC2**: ~$30-50/month (t3.medium)
- **RDS/Neon**: ~$20-40/month
- **S3**: ~$5-10/month
- **SSM**: <$5/month
- **CloudFlare**: Free tier
- **Total**: ~$60-100/month (sandbox)

## Support

- Check module READMEs in `infrastructure/modules/`
- Review `.envrc.example` for required variables
- See guides above for SSM and Turso specifics
