# Testing, Cost Verification & Security Scanning Guide

## Overview

This guide covers three essential aspects of infrastructure management:

1. **LocalStack Testing** - Test infrastructure locally without AWS costs
2. **Cost Estimation** - Estimate and verify AWS costs before deployment
3. **Security Scanning** - Identify and fix security vulnerabilities

---

## Part 1: LocalStack Testing

### What is LocalStack?

LocalStack is a fully functional local AWS cloud emulator that runs in Docker. It allows you to:

- ✅ Test infrastructure code locally
- ✅ Save money by avoiding AWS costs during development
- ✅ Iterate rapidly without cloud delays
- ✅ Test failure scenarios safely

### Architecture

```
Your Code (OpenTofu)
        ↓
    [LocalStack]
        ↓
    [Docker Container]
        ├── S3 Service
        ├── RDS Service
        ├── EC2 Service
        ├── Lambda Service
        └── ... (50+ AWS services)
```

### Quick Start

#### 1. Start LocalStack

```bash
# From iaac/ directory
docker-compose -f local/localstack.yml up -d

# Verify it's running
curl http://localhost:4566/_localstack/health
```

Expected output:

```json
{
  "services": {
    "s3": "running",
    "rds": "running",
    "ec2": "running",
    ...
  }
}
```

#### 2. Configure OpenTofu for LocalStack

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export TF_VAR_localstack_endpoint=http://localhost:4566
```

#### 3. Initialize and Deploy

```bash
# Initialize OpenTofu with LocalStack
tofu init \
  -backend-config="endpoint=http://localhost:4566" \
  -backend-config="bucket=tofu-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1"

# Plan deployment
tofu plan -var-file=infrastructure/environments/dev/terraform.tfvars

# Apply to LocalStack
tofu apply -var-file=infrastructure/environments/dev/terraform.tfvars
```

#### 4. Verify Resources

```bash
# List created resources
tofu output

# Check S3 buckets
aws s3 ls --endpoint-url=http://localhost:4566

# Check RDS instances
aws rds describe-db-instances --endpoint-url=http://localhost:4566
```

#### 5. Clean Up

```bash
# Destroy infrastructure
tofu destroy -var-file=infrastructure/environments/dev/terraform.tfvars

# Stop LocalStack
docker-compose -f local/localstack.yml down
```

### Available Services in LocalStack

The `local/localstack.yml` configuration enables:

| Service             | Use Case                           |
| ------------------- | ---------------------------------- |
| **S3**              | Object storage for assets, backups |
| **RDS**             | Database (PostgreSQL, MySQL)       |
| **EC2**             | Virtual machines, security groups  |
| **ECS**             | Container orchestration            |
| **Lambda**          | Serverless functions               |
| **ALB/ELB**         | Load balancing                     |
| **Route53**         | DNS management                     |
| **IAM**             | Identity & access control          |
| **Secrets Manager** | Sensitive data storage             |
| **CloudWatch**      | Logging & monitoring               |
| **DynamoDB**        | NoSQL database                     |
| **SQS/SNS**         | Message queues & topics            |

### Testing Workflow

```
┌─────────────────────────────────────────────┐
│ 1. Write Infrastructure Code (.tf files)    │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ 2. Start LocalStack (docker-compose up)     │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ 3. Configure Environment Variables          │
│    - AWS credentials (test/test)            │
│    - Endpoint: http://localhost:4566        │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ 4. Plan & Apply to LocalStack               │
│    - tofu plan                              │
│    - tofu apply                             │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ 5. Test Applications                        │
│    - Connect backend to local RDS           │
│    - Upload files to local S3               │
│    - Test Lambda functions                  │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ 6. Run Security & Cost Checks               │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ 7. Destroy LocalStack Resources             │
│    - tofu destroy                           │
│    - docker-compose down                    │
└─────────────────────────────────────────────┘
```

---

## Part 2: Cost Estimation & Verification

### What We'll Estimate

**Monthly costs for dev/staging/prod environments:**

- Compute (EC2, ECS)
- Storage (S3, RDS)
- Data Transfer
- Load Balancing
- Logging & Monitoring

### Tools We'll Use

#### 1. **Infracost** - Cost estimation from code

Infracost reads your Terraform/OpenTofu code and estimates AWS costs.

##### Installation

```bash
# macOS
brew install infracost

# Linux (from releases)
curl -s https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | bash

# Docker
docker run -it infracost/infracost --version
```

##### Setup API Key

```bash
# Free tier (5M API calls/month)
infracost auth login

# Or set manually
export INFRACOST_API_KEY=<your-key>
```

#### 2. **Using Infracost with OpenTofu**

```bash
# Generate cost estimate for dev environment
infracost breakdown \
  --path infrastructure/environments/dev/terraform.tfvars \
  --format json \
  > cost-estimate-dev.json

# Generate cost estimate for prod environment
infracost breakdown \
  --path infrastructure/environments/prod/terraform.tfvars \
  --format json \
  > cost-estimate-prod.json

# Compare costs between environments
infracost diff \
  --path infrastructure/environments/dev/terraform.tfvars \
  --compare-to infrastructure/environments/prod/terraform.tfvars
```

#### 3. **Cost Breakdown Example**

```
┌─────────────────────────────────────────────────────────┐
│ Monthly Cost Estimate (USD)                             │
├─────────────────────────────────────────────────────────┤
│ DEV Environment:                                        │
│  - EC2 (t3.micro): $7.50                               │
│  - RDS (db.t3.micro): $35.00                           │
│  - S3 (1GB storage): $0.02                             │
│  - Data Transfer: $2.00                                │
│  ────────────────────────────────────────────          │
│  Total: $44.52/month                                   │
│                                                         │
│ PROD Environment:                                       │
│  - EC2 (m5.large, 3x): $300.00                         │
│  - RDS (db.m5.large, Multi-AZ): $2,500.00            │
│  - S3 (1TB storage): $23.00                            │
│  - ALB: $16.00                                         │
│  - CloudWatch: $50.00                                  │
│  ────────────────────────────────────────────          │
│  Total: $2,889.00/month                                │
└─────────────────────────────────────────────────────────┘
```

#### 4. **Understanding Cost Structure**

**Compute Costs:**

- Instance type determines hourly rate
- Regional variations exist
- Reserved instances offer 30-70% discounts
- Spot instances offer 50-90% discounts

**Storage Costs:**

- S3: $0.023 per GB (standard, first 50TB)
- RDS: Varies by instance type (multi-AZ doubles cost)
- EBS: $0.10 per GB-month

**Data Transfer:**

- Outbound to internet: $0.09 per GB
- Between AWS regions: $0.02 per GB
- Within same region: FREE

**Optimization Tips:**

```
1. Use smaller instances in dev
2. Use reserved instances for prod (guaranteed usage)
3. Use spot instances for non-critical workloads
4. Enable S3 lifecycle policies to move old data to Glacier
5. Use VPC endpoints to avoid data transfer charges
6. Schedule resources (stop at night if not 24/7)
```

---

## Part 3: Security Scanning

### What is Security Scanning?

Security scanning analyzes your infrastructure code to find:

- ✅ Unencrypted resources
- ✅ Missing authentication
- ✅ Exposed secrets
- ✅ Non-compliant configurations
- ✅ Best practice violations

### Tools We'll Use

#### 1. **Checkov** - Infrastructure-as-Code scanning

Checkov is a static analysis tool that scans Terraform/OpenTofu code for security misconfigurations.

##### Installation

```bash
# Using pip
pip install checkov

# Using Homebrew
brew install checkov

# Using Docker
docker run -it bridgecrewio/checkov
```

##### Running Scans

```bash
# Scan entire infrastructure directory
checkov -d infrastructure/

# Scan specific environment
checkov -d infrastructure/environments/dev/

# Export results to JSON
checkov -d infrastructure/ --output json > security-scan.json

# Scan specific framework (terraform)
checkov -d infrastructure/ --framework terraform

# Check specific types
checkov -d infrastructure/ --check CKV_AWS_1,CKV_AWS_2
```

#### 2. **Tfsec** - Terraform security scanner

Tfsec is another security scanner with different checks than Checkov.

##### Installation

```bash
# Using brew
brew install tfsec

# Using Go
go install github.com/aquasecurity/tfsec/cmd/tfsec@latest

# Using Docker
docker run -it aquasec/tfsec
```

##### Running Scans

```bash
# Scan infrastructure directory
tfsec infrastructure/

# Generate JSON output
tfsec infrastructure/ --format json > tfsec-report.json

# Scan with minimal output
tfsec infrastructure/ --minimum-severity INFO
```

#### 3. **Understanding Security Checks**

**Common Security Issues:**

| Check                   | Severity | Example                        | Fix                       |
| ----------------------- | -------- | ------------------------------ | ------------------------- |
| **Unencrypted S3**      | HIGH     | S3 bucket without encryption   | Enable SSE-S3 or SSE-KMS  |
| **Open Security Group** | HIGH     | 0.0.0.0/0 access on port 22    | Restrict to specific IPs  |
| **RDS No Encryption**   | HIGH     | RDS without encryption enabled | Enable storage encryption |
| **No MFA on IAM**       | MEDIUM   | IAM user without MFA           | Require MFA               |
| **Missing Tags**        | LOW      | Resource without tags          | Add required tags         |
| **No Logging**          | MEDIUM   | ALB without access logs        | Enable access logging     |

#### 4. **Interpreting Results**

```
Example Checkov Output:

┌─────────────────────────────────────────────────┐
│ Check: CKV_AWS_1 - S3 Encryption               │
│ Severity: HIGH                                   │
│ Status: FAILED                                   │
├─────────────────────────────────────────────────┤
│ File: infrastructure/modules/s3-bucket/main.tf  │
│ Line: 12                                         │
│                                                  │
│ Current (insecure):                             │
│   resource "aws_s3_bucket" "data" {             │
│     bucket = "my-data"                          │
│   }                                             │
│                                                  │
│ Fixed (secure):                                 │
│   resource "aws_s3_bucket" "data" {             │
│     bucket = "my-data"                          │
│   }                                             │
│   resource "aws_s3_bucket_server_side_encryption_config" "data" {  │
│     bucket = aws_s3_bucket.data.id              │
│     rule {                                       │
│       apply_server_side_encryption_by_default { │
│         sse_algorithm = "AES256"                │
│       }                                         │
│     }                                           │
│   }                                             │
└─────────────────────────────────────────────────┘
```

#### 5. **Remediation Workflow**

```
1. Run checkov
        ↓
2. Review findings (HIGH → MEDIUM → LOW)
        ↓
3. Understand each issue
        ↓
4. Implement fix in code
        ↓
5. Re-run checkov to verify
        ↓
6. Commit changes to version control
```

---

## Part 4: Complete Testing Workflow

### Integrated Testing Script

Create `scripts/test-complete.sh`:

```bash
#!/bin/bash
set -e

echo "=== Payment Form Infrastructure Testing Suite ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Format Code
echo -e "${YELLOW}[1/6] Formatting OpenTofu code...${NC}"
tofu fmt -recursive infrastructure/
echo -e "${GREEN}✓ Code formatted${NC}\n"

# 2. Validate Syntax
echo -e "${YELLOW}[2/6] Validating OpenTofu syntax...${NC}"
tofu validate
echo -e "${GREEN}✓ Syntax valid${NC}\n"

# 3. Security Scan with Checkov
echo -e "${YELLOW}[3/6] Running Checkov security scan...${NC}"
checkov -d infrastructure/ --output json > security-checkov-report.json
echo -e "${GREEN}✓ Security scan complete (see security-checkov-report.json)${NC}\n"

# 4. Security Scan with Tfsec
echo -e "${YELLOW}[4/6] Running Tfsec security scan...${NC}"
tfsec infrastructure/ --format json > security-tfsec-report.json
echo -e "${GREEN}✓ Tfsec scan complete (see security-tfsec-report.json)${NC}\n"

# 5. Cost Estimation
echo -e "${YELLOW}[5/6] Estimating infrastructure costs...${NC}"
for ENV in dev staging prod; do
  if [ -f "infrastructure/environments/$ENV/terraform.tfvars" ]; then
    infracost breakdown \
      --path infrastructure/environments/$ENV/ \
      --format json > cost-estimate-$ENV.json
    echo -e "${GREEN}✓ Cost estimate for $ENV (see cost-estimate-$ENV.json)${NC}"
  fi
done
echo ""

# 6. LocalStack Testing
echo -e "${YELLOW}[6/6] Testing with LocalStack...${NC}"
echo "Starting LocalStack..."
docker-compose -f local/localstack.yml up -d

echo "Waiting for LocalStack to be ready..."
sleep 10

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "Initializing OpenTofu with LocalStack..."
tofu init \
  -backend-config="endpoint=http://localhost:4566" \
  -backend-config="bucket=tofu-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1"

echo "Planning infrastructure..."
tofu plan -var-file=infrastructure/environments/dev/terraform.tfvars -out=tfplan-local

echo "Applying to LocalStack..."
tofu apply tfplan-local

echo "Verifying resources..."
tofu output

echo "Cleaning up..."
tofu destroy -var-file=infrastructure/environments/dev/terraform.tfvars -auto-approve
docker-compose -f local/localstack.yml down

echo -e "${GREEN}✓ LocalStack testing complete${NC}\n"

echo -e "${GREEN}=== All Tests Complete ===${NC}"
echo ""
echo "📊 Reports Generated:"
echo "  - security-checkov-report.json"
echo "  - security-tfsec-report.json"
echo "  - cost-estimate-dev.json"
echo "  - cost-estimate-staging.json"
echo "  - cost-estimate-prod.json"
```

---

## Part 5: Makefile Integration

Add these targets to your Makefile:

```makefile
# LocalStack targets
localstack-start:
	@echo "Starting LocalStack..."
	docker-compose -f local/localstack.yml up -d
	@echo "LocalStack running at http://localhost:4566"
	@sleep 5
	@curl -s http://localhost:4566/_localstack/health | jq . || echo "LocalStack not ready yet"

localstack-stop:
	@echo "Stopping LocalStack..."
	docker-compose -f local/localstack.yml down

localstack-test: localstack-start
	@echo "Testing infrastructure with LocalStack..."
	export AWS_ACCESS_KEY_ID=test && \
	export AWS_SECRET_ACCESS_KEY=test && \
	export AWS_DEFAULT_REGION=us-east-1 && \
	tofu init -backend-config="endpoint=http://localhost:4566" && \
	tofu plan -var-file=infrastructure/environments/dev/terraform.tfvars && \
	tofu apply -var-file=infrastructure/environments/dev/terraform.tfvars -auto-approve && \
	tofu output && \
	tofu destroy -var-file=infrastructure/environments/dev/terraform.tfvars -auto-approve
	@make localstack-stop

# Cost estimation targets
cost-estimate-all:
	@for env in dev staging prod; do \
		echo "Estimating costs for $$env..."; \
		infracost breakdown --path infrastructure/environments/$$env/ --format json > cost-estimate-$$env.json; \
		echo "  ✓ cost-estimate-$$env.json"; \
	done

cost-estimate:
	@echo "Estimating costs for $(ENV) environment..."
	@infracost breakdown --path infrastructure/environments/$(ENV)/ --format table

# Security scanning targets
security-full: security-checkov security-tfsec
	@echo "✓ Full security scan complete"

security-checkov:
	@echo "Running Checkov security scan..."
	@checkov -d infrastructure/ --output json > security-checkov-report.json
	@checkov -d infrastructure/ --output cli
	@echo "Full report saved to: security-checkov-report.json"

security-tfsec:
	@echo "Running Tfsec security scan..."
	@tfsec infrastructure/ --format json > security-tfsec-report.json
	@tfsec infrastructure/ --format table
	@echo "Full report saved to: security-tfsec-report.json"

# Combined test targets
test-local: localstack-test

test-complete:
	@./scripts/test-complete.sh

test-security: security-full

test-costs: cost-estimate-all
```

---

## Quick Command Reference

```bash
# LocalStack
make localstack-start      # Start LocalStack
make localstack-stop       # Stop LocalStack
make localstack-test       # Full test cycle

# Cost Estimation
make cost-estimate ENV=dev      # Estimate costs for dev
make cost-estimate-all          # Estimate all environments

# Security Scanning
make security-checkov          # Run Checkov only
make security-tfsec            # Run Tfsec only
make security-full             # Run both scanners

# Complete Testing
make test-complete             # Run all tests
```

---

## Learning Path

### Week 1: Foundation

- [ ] Read this guide thoroughly
- [ ] Start LocalStack: `make localstack-start`
- [ ] Deploy to LocalStack: `make localstack-test`
- [ ] Review `local/localstack.yml` configuration

### Week 2: Cost Analysis

- [ ] Install Infracost
- [ ] Run: `make cost-estimate-all`
- [ ] Understand cost breakdown for each environment
- [ ] Identify optimization opportunities

### Week 3: Security

- [ ] Install Checkov and Tfsec
- [ ] Run: `make security-full`
- [ ] Review and fix HIGH severity issues
- [ ] Understand each CKV check

### Week 4: Integration

- [ ] Create test script: `scripts/test-complete.sh`
- [ ] Run: `make test-complete`
- [ ] Integrate into CI/CD pipeline
- [ ] Monitor costs and security regularly

---

## Troubleshooting

### LocalStack Issues

**Q: LocalStack won't start**

```bash
# Solution: Check Docker
docker ps
docker logs paymentform-localstack

# Solution: Check port availability
lsof -i :4566
```

**Q: Resources not created in LocalStack**

```bash
# Check OpenTofu state
tofu state list

# Check LocalStack services
curl http://localhost:4566/_localstack/health | jq .
```

### Cost Estimation Issues

**Q: Infracost returns empty results**

```bash
# Solution: Check API key
infracost auth login

# Solution: Use test endpoint
infracost breakdown --path infrastructure/environments/dev/ --format table
```

### Security Scanning Issues

**Q: Checkov doesn't find files**

```bash
# Check file paths
checkov -d infrastructure/ --list

# Use absolute paths
checkov -d /mnt/src/work/apps/paymentform-docker/iaac/infrastructure/
```

---

## Next Steps

1. **Implement Testing Locally** - Start with LocalStack
2. **Add Cost Monitoring** - Track actual vs estimated costs
3. **Setup CI/CD Integration** - Run tests on every commit
4. **Create Baseline** - Document current costs and security posture
5. **Monitor Regularly** - Track changes over time
