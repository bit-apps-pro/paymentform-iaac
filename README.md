# Payment Form Infrastructure as Code

Production-ready infrastructure for the Payment Form application using OpenTofu (Terraform), supporting multi-region deployment across AWS.

## 🚀 Quick Start

### Prerequisites
- OpenTofu >= 1.5 ([Install](https://opentofu.org/docs/intro/install/))
- AWS CLI configured with credentials
- Neon API key ([Get one here](https://neon.tech))
- Turso API token ([Get one here](https://turso.tech))
- `make` (optional, for convenience commands)

### Setup Databases

```bash
# 1. Create Neon account at https://neon.tech (main application DB)
# 2. Create Turso account at https://turso.tech (tenant databases)
# 3. Store credentials in AWS Secrets Manager
aws secretsmanager create-secret \
  --name neon-api-key \
  --secret-string "your-neon-api-key"

aws secretsmanager create-secret \
  --name turso-api-token \
  --secret-string "your-turso-token"

# 4. Export for Terraform
export TF_VAR_neon_api_key=$(aws secretsmanager get-secret-value \
  --secret-id neon-api-key \
  --query SecretString \
  --output text)

export TF_VAR_turso_api_token=$(aws secretsmanager get-secret-value \
  --secret-id turso-api-token \
  --query SecretString \
  --output text)
```

### Initialize Infrastructure

```bash
# From iaac/ directory
make init ENV=dev
```

Or use direct commands:

```bash
tofu init -backend-config=infrastructure/environments/dev/backend.hcl
```

## 📋 Common Operations

### Plan Changes
```bash
make plan ENV=dev                                    # Makefile
./tofu-wrapper.sh plan dev                          # Wrapper script
tofu plan -var-file=infrastructure/environments/dev/terraform.tfvars  # Direct
```

### Apply Changes
```bash
make apply ENV=dev
./tofu-wrapper.sh apply dev
tofu apply tfplan-dev
```

### Validate Configuration
```bash
make validate
./tofu-wrapper.sh validate
tofu validate
```

### Format & Lint
```bash
make fmt
./tofu-wrapper.sh fmt
tofu fmt -recursive infrastructure/
```

### Security Scanning
```bash
make security-scan
./tofu-wrapper.sh security-scan
checkov -d infrastructure/ --framework terraform
```

## 📁 Directory Structure

```
iaac/
├── main.tf                          # Root OpenTofu config (sources infrastructure/)
├── variables.tf                     # Root-level variables
├── outputs.tf                       # Root-level outputs
├── terraform.tfvars                 # Default variable values
├── Makefile                         # Convenience commands
├── tofu-wrapper.sh                  # Shell wrapper for OpenTofu
│
├── infrastructure/                  # Main infrastructure module
│   ├── main.tf                      # Infrastructure configuration
│   ├── variables.tf                 # Module variables
│   ├── outputs.tf                   # Module outputs
│   ├── terraform.tfvars             # Default values
│   │
│   ├── modules/                     # Reusable infrastructure modules
│   │   ├── neon/                    # Neon serverless PostgreSQL
│   │   ├── networking/              # VPC, subnets, security groups
│   │   ├── compute/                 # ECS, ALB, auto-scaling
│   │   ├── storage/                 # S3, storage resources
│   │   ├── security/                # IAM, KMS, encryption
│   │   └── ecs-service/             # ECS service definitions
│   │
│   ├── environments/                # Environment-specific configs
│   │   ├── dev/                     # Development environment
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.hcl
│   │   ├── staging/                 # Staging environment
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.hcl
│   │   └── prod/                    # Production environment
│   │       ├── terraform.tfvars
│   │       └── backend.hcl
│   │
│   ├── live/                        # Deployed infrastructure configs
│   │   ├── global/                  # Global resources
│   │   │   ├── databases/
│   │   │   ├── networking/
│   │   │   └── storage/
│   │   └── regional/                # Region-specific configs
│   │       ├── us-east-1/           # Backend services
│   │       ├── eu-west-1/           # Client services
│   │       └── ap-southeast-1/      # Renderer services
│   │
│   └── tests/                       # Infrastructure testing

├── ansible/                         # Configuration management
│   ├── playbooks/                   # Deployment playbooks
│   ├── roles/                       # Ansible roles
│   ├── inventory/                   # Inventory definitions
│   └── vars/                        # Variable files

├── local/                           # Local development
│   ├── docker-compose.*.yml         # Docker Compose files
│   ├── localstack.yml               # LocalStack for AWS emulation
│   └── data/                        # Local data volumes

├── scripts/                         # Helper scripts
│   ├── deploy-local.sh
│   ├── validate.sh
│   ├── rollback.sh
│   └── state-management.sh

└── docs/                            # Existing documentation
    ├── architecture.md
    ├── deployment-guide.md
    ├── secrets-management.md
    ├── monitoring-logging.md
    └── disaster-recovery.md
```

## 🎯 Environment Workflows

### Development Environment

Deploy cost-optimized infrastructure for testing:

```bash
make init ENV=dev
make plan ENV=dev
make apply ENV=dev

# Cleanup when done
make destroy ENV=dev
```

**Configuration:** Single region (us-east-1), small instance types, 7-day backup retention

### Staging Environment

Test production-like configuration before production:

```bash
make init ENV=staging
make plan ENV=staging
make apply ENV=staging
```

**Configuration:** Multi-region, production-grade, 14-day backup retention

### Production Environment

Deploy production infrastructure with full HA/DR:

```bash
make init ENV=prod
make plan ENV=prod -out=tfplan
# Review plan carefully
make apply ENV=prod
```

**Configuration:** Full multi-region HA, 30-day backup retention, enhanced security

## 🔧 Using Makefile Commands

All commands support environment selection with `ENV` variable:

```bash
# Common patterns
make help                    # Show all available commands
make init ENV=dev           # Initialize for environment
make plan ENV=staging       # Plan changes for environment
make apply ENV=prod         # Apply changes for environment
make destroy ENV=dev        # Destroy infrastructure
make validate               # Validate all configurations
make fmt                    # Format all .tf files
make lint                   # Validate and format
make security-scan          # Run Checkov security checks
make tfsec-scan            # Run tfsec security checks
make clean                  # Remove temporary files
make output ENV=dev        # Show outputs for environment
make state-list            # List resources in state
make refresh ENV=dev       # Refresh state
```

## 🧪 Testing & Validation

### Quick Testing (3 Steps)

```bash
# 1. Run complete testing suite
make test-complete

# 2. Test with LocalStack (local AWS emulation)
make localstack-test

# 3. Scan for security issues
make security-full
```

### Testing Components

#### 1. LocalStack Testing
Test infrastructure locally without AWS costs using Docker:

```bash
make localstack-start        # Start LocalStack container
make localstack-test         # Full test cycle (init → plan → apply → destroy)
make localstack-stop         # Stop LocalStack
```

**Benefits:**
- ✅ Test infrastructure without AWS costs
- ✅ Fast iteration during development
- ✅ Test failure scenarios safely
- ✅ Supports 50+ AWS services

#### 2. Security Scanning
Automatically scan for security misconfigurations:

```bash
make security-checkov        # Checkov compliance scanner
make security-tfsec          # Tfsec AWS security scanner
make security-full           # Run both scanners
```

**Checks:**
- Unencrypted S3 buckets
- Open security groups
- Missing authentication
- Best practice violations

#### 3. Cost Estimation
Estimate AWS costs before deployment:

```bash
make cost-estimate ENV=dev               # Single environment
make cost-estimate-all                   # All environments (dev/staging/prod)
```

**Output:** Monthly cost estimates per service

#### 4. Complete Testing Suite
Run all tests in sequence:

```bash
make test-complete

# This runs:
# 1. Code formatting & validation
# 2. Checkov security scan
# 3. Tfsec security scan
# 4. Cost estimation (all environments)
# 5. LocalStack deployment test
# 6. Resource verification
```

### Testing Documentation

For comprehensive guides, see:
- **[Testing Quick Start](./TESTING-QUICK-START.md)** - Fast reference for all testing commands
- **[Full Testing Guide](./docs/testing-and-validation.md)** - Detailed explanations with examples
- **[Cost Estimation Guide](./docs/cost-estimation.md)** - How to count costs before deployment
- **[Best Practices](./docs/best-practices.md)** - Dos & Don'ts, cost optimization, things to avoid

---

## �️ Database: Neon (Serverless PostgreSQL)

This infrastructure uses **Neon** instead of RDS for significant cost savings and zero management.

### Neon Benefits
- ✅ 75% cheaper than RDS (pay-per-use)
- ✅ Automatic scaling and backups
- ✅ Built-in connection pooling
- ✅ Point-in-time recovery
- ✅ Encryption at rest & in transit
- ✅ Free tier for development

### Get Database Connection

```bash
# After deployment, retrieve connection details
tofu output -json | jq '.database_host, .database_name, .database_app_role'

# Get connection string
tofu output -raw neon_connection_string
```

### Update Laravel .env

```bash
DB_CONNECTION=pgsql
DB_HOST=<database_host from output>

### Standard Deployment

1. **Plan changes** in isolated environment
2. **Review plan** for unexpected changes
3. **Get approval** for production changes
4. **Apply changes** using saved plan
5. **Verify** resources are created correctly
6. **Monitor** metrics and logs

### Example

```bash
# Development - quick iteration
make plan ENV=dev
make apply ENV=dev

# Staging - full test
make plan ENV=staging
make apply ENV=staging

# Production - careful promotion
make plan ENV=prod -out=tfplan
# Review tfplan
make apply ENV=prod
```

### Rollback Procedure

If deployment fails or needs rollback:

```bash
# For state-based rollback (if versioning enabled)
aws s3api list-object-versions \
  --bucket paymentform-terraform-state-prod

# Restore previous state version and apply
make apply ENV=prod
```

## 🧪 Validation & Testing

### Before Every Deployment

```bash
# Syntax validation
tofu validate

# Format check
tofu fmt -recursive infrastructure/

# Security scanning
checkov -d infrastructure/ --framework terraform
tfsec infrastructure/
```

### Using Makefile

```bash
# All in one
make lint

# Individual checks
make validate
make fmt
make security-scan
```

## 📊 State Management

### State Files Location

| Environment | Bucket | Path |
|-------------|--------|------|
| Development | `paymentform-terraform-state-dev` | `dev/terraform.tfstate` |
| Staging | `paymentform-terraform-state-staging` | `staging/terraform.tfstate` |
| Production | `paymentform-terraform-state-prod` | `prod/terraform.tfstate` |

### State Operations

```bash
# List resources in state
tofu state list

# Show specific resource details
tofu state show 'module.infrastructure.aws_instance.example'

# Refresh state from AWS
tofu refresh -var-file=infrastructure/environments/dev/terraform.tfvars

# Manual state manipulation (use cautiously)
tofu state rm 'resource.id'
tofu state mv 'old.resource' 'new.resource'
```

## 🔍 Common Issues & Troubleshooting

### Issue: "Error acquiring the state lock"

**Cause:** Another operation has the state lock  
**Solution:**
```bash
# Find lock ID
tofu state show

# Force unlock (use only if process is truly stuck)
tofu force-unlock <lock-id>
```

### Issue: "Resource already exists in AWS"

**Cause:** Resource created outside of OpenTofu  
**Solution:**
```bash
# Import existing resource into state
tofu import 'resource.type' <resource-id>
```

### Issue: "Invalid credentials"

**Cause:** AWS credentials not configured  
**Solution:**
```bash
# Configure AWS credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_DEFAULT_REGION=us-east-1
```

## 📈 Multi-Region Strategy

### Regional Distribution

| Region | Purpose | Services |
|--------|---------|----------|
| us-east-1 | Primary | Backend, Primary DB, Main ALB |
| eu-west-1 | Secondary | Client Dashboard, Read Replica |
| ap-southeast-1 | Tertiary | Renderer, Read Replica |

### Deployment Across Regions

```bash
# Deploy to primary region
make apply ENV=prod  # us-east-1

# Cross-region replication happens automatically
# Verify secondary regions
tofu output -var-file=infrastructure/environments/prod/terraform.tfvars
```

## 🔄 CI/CD Integration

### Prerequisites for Automation

- AWS credentials with appropriate permissions
- GitHub Actions or GitLab CI runner configured
- Pre-commit hooks installed locally

### Typical Pipeline

1. Push code to branch
2. ✅ Syntax validation (`tofu validate`)
3. ✅ Security scanning (Checkov, tfsec)
4. ✅ Plan generation (`tofu plan`)
5. ✅ PR comments with changes
6. ✅ Manual approval for production
7. ✅ Auto-deployment on merge

## 📚 Additional Resources

### Existing Documentation
- **Architecture:** `docs/architecture.md`
- **Deployment:** `docs/deployment-guide.md`
- **Secrets:** `docs/secrets-management.md`
- **Monitoring:** `docs/monitoring-logging.md`
- **Disaster Recovery:** `docs/disaster-recovery.md`

### External Resources
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Infrastructure Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)

## ⚠️ Important Notes

### Before Production Deployment

- [ ] State backend is configured and tested
- [ ] All variables are set correctly
- [ ] Security scanning passed
- [ ] Team has reviewed plan
- [ ] Approval obtained
- [ ] Rollback plan documented
- [ ] Monitoring configured
- [ ] Backups enabled

### Never

- ❌ Commit state files to git
- ❌ Hardcode secrets in configurations
- ❌ Share AWS credentials
- ❌ Modify state manually without backup
- ❌ Deploy without testing in lower environment
- ❌ Skip security scanning
- ❌ Ignore validation errors

## 🆘 Support & Questions

### Quick Help

```bash
make help                    # Show all Makefile targets
./tofu-wrapper.sh help      # Show wrapper script help
tofu help                   # Show OpenTofu help
```

### Team Communication

- **Slack:** #infrastructure
- **Email:** infrastructure-team@company.com
- **Docs:** See `docs/` directory
- **On-Call:** Check PagerDuty schedule

## 📝 Version Information

- **OpenTofu:** >= 1.5
- **AWS Provider:** ~> 5.0
- **Last Updated:** January 2026
- **Maintainer:** Infrastructure Team

---

**Start with:** `make help` to see all available commands

**Next Steps:** Choose your environment (dev/staging/prod) and follow the workflow above
