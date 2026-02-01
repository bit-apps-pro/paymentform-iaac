# AGENT.md - Infrastructure Context

> **Purpose**: Quick reference for AI agents working on Payment Form infrastructure

## Project Overview

**Name**: Payment Form Infrastructure as Code  
**Tool**: OpenTofu (Terraform fork)  
**Cloud**: AWS  
**Deployment**: Multi-region backend, Global CDN frontend

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│ Frontend (Global CDN)                                        │
│ - Client: app.{domain} → CloudFront + S3                    │
│ - Renderer: *.{domain} → CloudFront + S3 (wildcard)         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ Backend (Multi-Region)                                       │
│ - API: api.{domain} → ALB (us-east-1, eu-west-1, ap-se-1)  │
│ - FrankenPHP + libsql extension                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ Databases                                                     │
│ - Neon: Central PostgreSQL (accounts, billing)              │
│ - Turso: Edge SQLite per tenant (forms, submissions)        │
└─────────────────────────────────────────────────────────────┘
```

## Environments

| Environment | Domain | API | Client | Renderer | Purpose |
|-------------|--------|-----|--------|----------|---------|
| **dev** | `dev.paymentform.local` | `api.dev.paymentform.local` | `app.dev.paymentform.local` | `*.dev.paymentform.local` | Local testing |
| **sandbox** | `sandbox.paymentform.io` | `api.sandbox.paymentform.io` | `app.sandbox.paymentform.io` | `*.sandbox.paymentform.io` | Public testing |
| **prod** | `paymentform.io` | `api.paymentform.io` | `app.paymentform.io` | `*.paymentform.io` | Production |

## Directory Structure

```
iaac/
├── main.tf                          # Root module (sources infrastructure/)
├── variables.tf                     # Root variables
├── terraform.tfvars                 # Default values (DO NOT commit secrets)
├── Makefile                         # Convenience commands
├── tofu-wrapper.sh                  # Shell wrapper
│
├── infrastructure/                  # Main infrastructure module
│   ├── main.tf                      # Module orchestration
│   ├── variables.tf                 # Module variables
│   ├── outputs.tf                   # Module outputs
│   │
│   ├── modules/                     # Reusable components
│   │   ├── neon/                    # Neon PostgreSQL (central DB)
│   │   ├── turso/                   # Turso SQLite (tenant DBs)
│   │   ├── networking/              # VPC, subnets, security groups
│   │   ├── compute/                 # ECS, ALB, auto-scaling
│   │   ├── storage/                 # S3, CloudFront
│   │   ├── security/                # IAM, KMS
│   │   └── alb/                     # Application Load Balancers
│   │
│   └── environments/                # Environment configs
│       ├── dev/
│       │   ├── terraform.tfvars     # Dev-specific values
│       │   └── backend.hcl          # Dev state backend
│       ├── sandbox/
│       │   ├── terraform.tfvars     # Sandbox values
│       │   └── backend.hcl          # Sandbox state backend
│       ├── prod/
│       │   ├── terraform.tfvars     # Prod values
│       │   └── backend.hcl          # Prod state backend
│       ├── dev.tfvars               # Dev shorthand
│       ├── sandbox.tfvars           # Sandbox shorthand
│       └── prod.tfvars              # Prod shorthand
│
├── ansible/                         # Configuration management
│   ├── playbooks/                   # Deployment playbooks
│   │   ├── deploy-backend.yml
│   │   ├── deploy-client.yml
│   │   └── deploy-renderer.yml
│   └── vars/
│       ├── dev.yml
│       ├── sandbox.yml
│       └── prod.yml
│
├── docs/                            # Documentation
│   ├── architecture.md              # System architecture
│   ├── architectural-decisions.md   # ADR (WHY we chose things)
│   ├── subdomain-configuration.md   # DNS/subdomain setup
│   ├── deployment-guide.md
│   ├── cost-estimation.md
│   ├── secrets-management.md
│   ├── monitoring-logging.md
│   └── disaster-recovery.md
│
├── DECISIONS-SUMMARY.md             # Quick answers to arch questions
└── AGENT.md                         # This file
```

## Key Decisions (WHY)

### Database Strategy
- **Neon**: Central PostgreSQL - 75% cheaper than RDS, serverless
- **Turso**: Per-tenant SQLite - Ultra-low latency, edge replication
- **Split**: Central data in Neon, tenant data in Turso

### Multi-Tenancy
- **Wildcard DNS**: `*.{domain}` → Instant provisioning, unlimited scale
- **Alternative**: On-demand DNS via Cloudflare API (for enterprise custom domains only)
- **WHY**: Wildcard = no API limits, no propagation delays

### Container Registry
- **GitHub Container Registry (GHCR)**: $0-25/month vs ECR $50-100/month
- **WHY**: Free tier is generous, tight GitHub Actions integration

### Region Detection (Tenant DB Location)
- **Cloudflare CF-IPCountry header**: Maps country → closest Turso region
- **User override**: tenant->data['turso_region'] takes priority
- **Fallback**: TURSO_DEFAULT_REGION config
- **WHY**: No external API calls, sub-millisecond detection

### Backend Runtime
- **FrankenPHP**: Native libsql extension for Turso
- **WHY**: 3-5x better performance than PHP-FPM, single binary

## Variables Reference

### Required Variables (Root)
```hcl
neon_api_key      # Sensitive, get from: https://neon.tech
turso_api_token   # Sensitive, get from: turso auth token
environment       # dev | sandbox | prod
region            # AWS region (us-east-1)
desired_capacity  # Auto-scaling group size
```

### Domain Variables
```hcl
domain_name        # Base domain (e.g., sandbox.paymentform.io)
api_subdomain      # Backend API (e.g., api.sandbox.paymentform.io)
app_subdomain      # Client dashboard (e.g., app.sandbox.paymentform.io)
renderer_subdomain # Multi-tenant (e.g., *.sandbox.paymentform.io)
```

## Common Commands

```bash
# Initialize
make init ENV=sandbox

# Plan
make plan ENV=sandbox

# Apply
make apply ENV=sandbox

# Destroy
make destroy ENV=sandbox

# Check outputs
make output ENV=sandbox

# Cost estimate
make cost-estimate ENV=sandbox

# Security scan
make security-scan

# Format
make fmt

# Validate
make validate

# All tests
make test-complete
```

## State Management

| Environment | S3 Bucket | Key | Lock Table |
|-------------|-----------|-----|------------|
| dev | `paymentform-terraform-state-dev` | `dev/terraform.tfstate` | `paymentform-terraform-lock` |
| sandbox | `paymentform-terraform-state-sandbox` | `sandbox/terraform.tfstate` | `paymentform-terraform-lock` |
| prod | `paymentform-terraform-state-prod` | `prod/terraform.tfstate` | `paymentform-terraform-lock` |

**State Operations**:
```bash
# List resources
tofu state list

# Show resource
tofu state show 'module.infrastructure.aws_instance.example'

# Refresh
tofu refresh -var-file=infrastructure/environments/sandbox/terraform.tfvars

# Import existing resource
tofu import 'resource.type' <resource-id>
```

## Secrets Management

**DO NOT commit**:
- `*.tfvars` with actual secrets
- `terraform.tfvars` with credentials
- Any file with API keys, passwords, tokens

**Use**:
- AWS Secrets Manager for production
- Environment variables for development
- `.gitignore` includes sensitive patterns

**Setup**:
```bash
# Store in AWS Secrets Manager
aws secretsmanager create-secret \
  --name neon-api-key \
  --secret-string "your-key"

# Export for Terraform
export TF_VAR_neon_api_key=$(aws secretsmanager get-secret-value \
  --secret-id neon-api-key \
  --query SecretString \
  --output text)
```

## DNS/SSL Configuration

### DNS Records (Per Environment)
```
A    api.{domain}     → ALB
A    app.{domain}     → CloudFront
A    *.{domain}       → CloudFront (wildcard for tenants)
```

### SSL Certificates (ACM)
**Must be in us-east-1** for CloudFront:
```
Primary: {domain}
SANs: api.{domain}, app.{domain}, *.{domain}
```

## Cost Estimates

| Environment | Monthly | Notes |
|-------------|---------|-------|
| dev | $60-100 | Single region, t3.micro |
| sandbox | $300-500 | Production-like, cost-optimized |
| prod | $800-1500+ | Multi-region HA, auto-scaling |

## Deployment Workflow

```
┌──────────┐
│   DEV    │ Local testing
└────┬─────┘
     │
     ↓
┌──────────┐
│ SANDBOX  │ Public testing (sandbox.paymentform.io)
└────┬─────┘ Test multi-region, CDN, edge cases
     │
     ↓
┌──────────┐
│   PROD   │ Production (paymentform.io)
└──────────┘ Full HA, monitoring, backups
```

## Module Dependencies

```
networking → security → alb → compute
                    ↓
                 storage → cloudfront
                    ↓
              neon + turso
```

## Important Notes

### Wildcard Subdomain
- Single DNS record: `*.sandbox.paymentform.io`
- Traefik/CloudFront routes based on Host header
- Unlimited tenants, zero DNS changes

### Turso Groups
- Databases organized by groups
- Groups define primary region
- Created automatically per region (e.g., `group-lhr`, `group-ord`)

### CloudFront Considerations
- Cache invalidation required on deploy
- Propagation takes 5-10 minutes
- ACM cert must be in us-east-1

### Multi-Region Backend
- Route53 latency-based routing
- Health checks required for failover
- Sessions must be stateless or use shared storage

## Troubleshooting

### "No state file found"
```bash
# Initialize backend first
make init ENV=sandbox
```

### "Lock acquisition failed"
```bash
# Someone else running or crashed operation
# Force unlock (ONLY if stuck)
tofu force-unlock <lock-id>
```

### "Certificate validation pending"
```bash
# Add DNS validation records to Route53
# Check ACM console for CNAME records needed
```

### "Module not found"
```bash
# Re-initialize to download modules
tofu init -upgrade
```

## File Naming Conventions

- `main.tf` - Primary resource definitions
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `*.tfvars` - Variable values (DO NOT commit with secrets)
- `backend.hcl` - State backend configuration

## Testing

```bash
# Local validation
make validate

# Security scanning
make security-scan

# Cost estimation
make cost-estimate ENV=sandbox

# LocalStack (AWS emulation)
make localstack-test

# Complete test suite
make test-complete
```

## Related Documentation

- **Architecture**: `docs/architecture.md` - System design details
- **Decisions**: `docs/architectural-decisions.md` - WHY we chose things
- **Deployment**: `docs/deployment-guide.md` - Step-by-step deploy
- **Subdomains**: `docs/subdomain-configuration.md` - DNS/SSL setup
- **Quick Ref**: `DECISIONS-SUMMARY.md` - Fast answers

## Quick Reference Links

- [OpenTofu Docs](https://opentofu.org/docs/)
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Neon](https://neon.tech) - Central PostgreSQL
- [Turso](https://turso.tech) - Edge SQLite

## Common Patterns

### Adding a new environment
1. Create `infrastructure/environments/{env}/`
2. Add `terraform.tfvars` and `backend.hcl`
3. Update `Makefile` targets
4. Create S3 bucket for state
5. Create DynamoDB table for locking

### Adding a new module
1. Create `infrastructure/modules/{name}/`
2. Add `main.tf`, `variables.tf`, `outputs.tf`
3. Source in `infrastructure/main.tf`
4. Pass variables from root

### Changing subdomain structure
1. Update `variables.tf` (domain variables)
2. Update `environments/{env}/*.tfvars`
3. Update DNS records in Route53 module
4. Update SSL certificate SANs
5. Update CloudFront distributions

## Security Checklist

- [ ] Never commit secrets to git
- [ ] Use AWS Secrets Manager for production
- [ ] Enable state encryption
- [ ] Enable state versioning
- [ ] Use least-privilege IAM roles
- [ ] Enable CloudTrail logging
- [ ] Scan with security tools before apply
- [ ] Review plan before production apply
- [ ] Enable MFA for state bucket access

## Cost Optimization

- Dev: t3.micro instances, single AZ, 7-day backups
- Sandbox: t3.small instances, multi-AZ, 14-day backups
- Prod: t3.large+ instances, multi-region, 30-day backups
- Use Neon (not RDS) for 75% savings
- Use GitHub Container Registry (not ECR) for savings
- CloudFront caching reduces origin costs

## Monitoring

- CloudWatch for AWS resources
- ECS Container Insights for containers
- Application logs → CloudWatch Logs
- Health checks on ALB
- Route53 health checks for failover
- Cost alerts via AWS Budgets

---

**Last Updated**: 2026-02-01  
**Maintained By**: Infrastructure Team  
**Version**: 1.0

For questions or issues, check the docs/ directory or refer to DECISIONS-SUMMARY.md for quick answers.
