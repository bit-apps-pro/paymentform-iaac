# Infrastructure Development Best Practices & Cost Optimization

## 🎯 DO's - Follow These

### Infrastructure as Code

✅ **DO use version control for all infrastructure**

```bash
git commit -m "Add RDS multi-AZ support"
git push origin feature/rds-improvements
```

- Track all infrastructure changes
- Enable rollback capabilities
- Collaborate safely with team

✅ **DO separate code by environment**

```
infrastructure/
├── environments/
│   ├── dev/terraform.tfvars
│   ├── staging/terraform.tfvars
│   └── prod/terraform.tfvars
```

- Different variables per environment
- Prevent accidental prod changes
- Easy environment-specific tweaks

✅ **DO use modules for reusability**

```hcl
module "networking" {
  source = "./modules/networking"
  cidr_block = var.vpc_cidr
}
```

- DRY principle (Don't Repeat Yourself)
- Consistent resource configuration
- Easy to maintain and update

✅ **DO validate before applying**

```bash
make validate         # Check syntax
make fmt             # Format code
make plan ENV=dev    # Review changes
make apply ENV=dev   # Deploy
```

- Catch errors early
- Review changes first
- Prevent accidental issues

✅ **DO use descriptive names**

```hcl
resource "aws_instance" "api_server_prod" {
  # Good: clear purpose and environment
}

resource "aws_instance" "server1" {
  # Bad: unclear
}
```

✅ **DO implement security best practices**

```hcl
# Good: encrypted database
resource "aws_db_instance" "main" {
  storage_encrypted = true
  backup_retention_period = 30
}

# Good: restricted security group
resource "aws_security_group" "app" {
  ingress {
    from_port = 443
    to_port = 443
    cidr_blocks = ["10.0.0.0/8"]  # Restricted
  }
}
```

✅ **DO document your infrastructure**

```hcl
# Describes the main application database
# Multi-AZ for high availability
# Encrypted with KMS
resource "aws_db_instance" "application_db" {
  # configuration...
}
```

✅ **DO test infrastructure locally**

```bash
make install-tools    # Setup testing tools
make localstack-test  # Test with LocalStack
```

- Catch issues before AWS deployment
- Zero costs for development testing
- Fast iteration cycles

✅ **DO scan for security issues**

```bash
make security-full    # Run Checkov + Tfsec
```

- Find vulnerabilities early
- Fix before production deployment
- Meet compliance requirements

✅ **DO estimate costs before deployment**

```bash
make cost-estimate ENV=prod    # Review costs
```

- Budget awareness
- Avoid surprises
- Identify optimization opportunities

✅ **DO use remote state with locking**

```hcl
backend "s3" {
  bucket = "terraform-state"
  dynamodb_table = "terraform-locks"  # Prevents concurrent modifications
  encrypt = true
}
```

✅ **DO tag all resources**

```hcl
tags = {
  Environment = "prod"
  Project = "payment-form"
  Owner = "platform-team"
  CostCenter = "engineering"
}
```

- Track costs by project/team
- Easier resource management
- Compliance reporting

---

## ❌ DON'Ts - Avoid These

### Infrastructure Mistakes

❌ **DON'T commit sensitive data to git**

```bash
# Bad: credentials in code
variable "db_password" {
  default = "MyPassword123"
}

# Good: use AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  # retrieve from secrets manager
}
```

❌ **DON'T use default VPC**

```bash
# Bad: using default VPC
resource "aws_instance" "server" {
  # no vpc_id specified
}

# Good: explicit VPC
resource "aws_instance" "server" {
  vpc_id = aws_vpc.main.id
  subnet_id = aws_subnet.private.id
}
```

❌ **DON'T manually create/modify resources outside IaC**

```bash
# Bad: manually creating in AWS console
# Instead, define in .tf files and apply

# Good: all infrastructure in code
resource "aws_s3_bucket" "app_data" {
  # configuration...
}
```

- Prevents drift (mismatch between code and reality)
- Keeps IaC source of truth
- Reproducible infrastructure

❌ **DON'T ignore state management**

```bash
# Bad: checking .tfstate into git
git add *.tfstate

# Good: remote state with encryption
terraform {
  backend "s3" {
    encrypt = true
  }
}
```

❌ **DON'T use hardcoded values**

```hcl
# Bad: hardcoded
resource "aws_instance" "web" {
  instance_type = "t3.medium"
  ami = "ami-12345678"
}

# Good: variables
resource "aws_instance" "web" {
  instance_type = var.instance_type
  ami = data.aws_ami.ubuntu.id
}
```

❌ **DON'T open security groups too wide**

```hcl
# Bad: open to entire internet
ingress {
  from_port = 22
  to_port = 22
  cidr_blocks = ["0.0.0.0/0"]
}

# Good: restricted access
ingress {
  from_port = 22
  to_port = 22
  security_groups = [aws_security_group.bastion.id]
}
```

❌ **DON'T skip backups**

```hcl
# Bad: no backups
resource "aws_db_instance" "main" {
  backup_retention_period = 0
}

# Good: backups enabled
resource "aws_db_instance" "main" {
  backup_retention_period = 30
  backup_window = "03:00-04:00"
}
```

❌ **DON'T use single-AZ in production**

```hcl
# Bad: single point of failure
resource "aws_db_instance" "main" {
  multi_az = false
}

# Good: multi-AZ
resource "aws_db_instance" "main" {
  multi_az = true  # Automatic failover
}
```

❌ **DON'T ignore monitoring/logging**

```hcl
# Bad: no logs
resource "aws_alb" "main" {
  # no logging configured
}

# Good: logging enabled
resource "aws_lb" "main" {
  access_logs {
    bucket = aws_s3_bucket.logs.id
    enabled = true
  }
}
```

❌ **DON'T deploy without approval**

```bash
# Bad: direct apply
tofu apply

# Good: plan, review, approve, apply
tofu plan -out=tfplan
# Review tfplan
tofu apply tfplan
```

---

## 💰 Cost Optimization Strategies

### 1. Right-Size Your Instances

**Development Environment**

```hcl
# Good for dev: cheap, small instances
variable "instance_type" {
  default = "t3.micro"  # ~$8/month
}
```

**Staging Environment**

```hcl
# Good for staging: production-like but smaller
variable "instance_type" {
  default = "t3.small"  # ~$20/month
}
```

**Production Environment**

```hcl
# Production: appropriate size for workload
variable "instance_type" {
  default = "m5.large"  # Baseline, then scale
}
```

💡 **Start small, scale up based on metrics**

### 2. Use Reserved Instances (RI)

```hcl
# EC2 instances you'll keep running 24/7
# Buy 1-year or 3-year reserved instances
# Saves 30-70% vs on-demand

# 1 year: 30% discount
# 3 year: 60% discount
```

**Example savings:**

- m5.large on-demand: $96/month
- m5.large 1-year RI: $67/month (30% savings = $29 saved)
- m5.large 3-year RI: $38/month (60% savings = $58 saved)

### 3. Use Spot Instances for Non-Critical Workloads

```hcl
resource "aws_instance" "batch_processor" {
  instance_type = "m5.large"
  spot_price = "0.03"  # 70% cheaper than on-demand
  # Good for: batch jobs, CI/CD, non-critical services
}
```

**Savings:** 70-90% discount  
**Trade-off:** Can be interrupted (acceptable for batch jobs)

### 4. Schedule Resources

```hcl
# Stop dev/staging at night and weekends
# Use CloudWatch + Lambda to schedule start/stop

# Example savings:
# Dev instance: $8/month * 50% (stopped nights/weekends) = $4/month
```

### 5. Optimize Database Costs

**Development**

```hcl
resource "aws_db_instance" "dev" {
  instance_class = "db.t3.micro"      # Cheapest
  allocated_storage = 20              # Minimal
  backup_retention_period = 7         # 7 days
  multi_az = false                    # Single AZ
  # Monthly cost: ~$35
}
```

**Production**

```hcl
resource "aws_db_instance" "prod" {
  instance_class = "db.m5.large"      # Appropriate
  allocated_storage = 100             # Larger
  backup_retention_period = 30        # 30 days
  multi_az = true                     # High availability
  # Monthly cost: ~$2,500+
}
```

**Cost optimization tips:**

- ✅ Use provisioned IOPS only if needed
- ✅ Consider Aurora (24/7 pricing better for databases)
- ✅ Use read replicas for read-heavy workloads
- ✅ Archive old logs to Glacier

### 6. Optimize Storage Costs

**S3 Bucket Lifecycle**

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.data.id

  rule {
    id = "archive_old_data"

    transition {
      days = 30
      storage_class = "STANDARD_IA"  # Cheaper after 30 days
    }

    transition {
      days = 90
      storage_class = "GLACIER"      # Very cheap for archive
    }
  }
}
```

**Savings Example:**

- New data (30 days): $0.023/GB/month (Standard)
- Old data (30-90 days): $0.0125/GB/month (Standard-IA) = 46% savings
- Archive (90+ days): $0.004/GB/month (Glacier) = 83% savings

### 7. Use CloudFront for Distribution

```hcl
resource "aws_cloudfront_distribution" "content" {
  # Serve content globally
  # Reduces data transfer costs
  # Caches at edge locations
}
```

**Savings:** Reduces AWS data transfer costs by 50-80%

### 8. Consolidate Resources

```hcl
# Bad: separate RDS for each microservice
resource "aws_db_instance" "service_a" { }
resource "aws_db_instance" "service_b" { }
resource "aws_db_instance" "service_c" { }
# Cost: $2,500 × 3 = $7,500/month

# Good: shared database with separate schemas
resource "aws_db_instance" "shared" {
  allocated_storage = 150
  # Use separate schemas/users for each service
}
# Cost: $2,500/month + network costs (minimal)
```

### 9. Use Auto-Scaling

```hcl
resource "aws_autoscaling_group" "app" {
  min_size = 2
  max_size = 10
  desired_capacity = 2  # Adjust based on load
}
```

**Benefits:**

- ✅ Pay only for what you use
- ✅ Automatic scale down during low traffic
- ✅ Scale up for peak demand

### 10. Monitor and Alert on Costs

```bash
# Use Infracost to track estimated costs
make cost-estimate-all

# Set up AWS billing alerts
# Alert when monthly bill reaches certain threshold
```

---

## 🚨 Things to Avoid

### Performance Issues That Cost Money

❌ **Don't use undersized instances** (causes high CPU → scaling + costs)

```hcl
# Bad: undersized, will auto-scale to max
instance_type = "t3.micro"  # Can't handle load

# Good: appropriate size
instance_type = "m5.large"  # Handles load, minimal scaling
```

❌ **Don't ignore database performance** (slow queries = higher costs)

```bash
# Monitor query performance
# Add indexes to slow queries
# Use RDS performance insights
```

❌ **Don't use non-production pricing for production** (overpaying)

```hcl
# Bad: using on-demand for 24/7 baseline
# Cost: expensive

# Good: using reserved instances
# Cost: 60% cheaper
```

### Compliance & Security Issues

❌ **Don't skip encryption**

- Unencrypted data = compliance failures
- Encrypted data = minimal cost difference

❌ **Don't ignore IAM permissions** (security breach risk)

```hcl
# Always use least-privilege principle
# Most expensive incident: data breach
```

❌ **Don't leave resources running when not needed**

```bash
# Dev/staging resources should stop at 6 PM
# Production should be optimized for RI/savings plans
```

### Data Transfer Costs

❌ **Don't transfer data across regions unnecessarily**

```
# Data transfer costs:
# Within region: FREE
# Between regions: $0.02/GB
# To internet: $0.09/GB (most expensive)
```

**Save data transfer costs:**

- ✅ Use VPC endpoints (free data transfer)
- ✅ Keep resources in same region
- ✅ Use CloudFront for global distribution

### Common Architecture Mistakes

❌ **Don't use EBS when S3 would work**

```hcl
# Bad: EBS volume always running
resource "aws_ebs_volume" "storage" {
  size = 100
  # Cost: $10/month whether you use it or not
}

# Good: S3 for static files
resource "aws_s3_bucket" "storage" {
  # Cost: only pay for what you store ($0.023/GB)
}
```

❌ **Don't use NAT Gateway in dev**

```hcl
# Bad: NAT Gateway in dev ($32/month + data transfer)
resource "aws_nat_gateway" "dev" { }

# Good: NAT Instance or VPN
# Cost: ~$3/month (t3.micro instance)
```

❌ **Don't use expensive resources for non-critical services**

```hcl
# Bad: prod-grade database for logs
resource "aws_db_instance" "logs" {
  instance_class = "db.m5.large"  # Too expensive
}

# Good: use appropriate service
resource "aws_cloudwatch_log_group" "logs" {
  # Cost: pay only for ingestion/storage
}
```

---

## 📊 Cost Breakdown Example

### Development Environment (Monthly)

| Resource      | Size        | Cost     | Notes                    |
| ------------- | ----------- | -------- | ------------------------ |
| EC2           | t3.micro    | $8       | Dev server               |
| RDS           | db.t3.micro | $35      | Single AZ, 7-day backups |
| S3            | 50GB        | $1.15    | Data storage             |
| **Total Dev** |             | **~$45** | Very affordable          |

### Production Environment (Monthly)

| Resource       | Size        | Cost        | Notes                    |
| -------------- | ----------- | ----------- | ------------------------ |
| EC2 (Reserved) | m5.large ×3 | $190        | 1-year RI (60% savings)  |
| RDS (Reserved) | db.m5.large | $1,200      | Multi-AZ, 30-day backups |
| ALB            | 1           | $16         | Load balancer            |
| NAT Gateway    | 1           | $32         | Outbound traffic         |
| CloudFront     |             | $50         | Distribution             |
| Data Transfer  |             | $100        | Global users             |
| Monitoring     |             | $50         | CloudWatch, logs         |
| **Total Prod** |             | **~$1,638** | With optimizations       |

---

## ✅ Pre-Deployment Checklist

- [ ] Code reviewed and approved
- [ ] All tests passing (`make test-complete`)
- [ ] Security scan clean (`make security-full`)
- [ ] Costs estimated and approved (`make cost-estimate ENV=prod`)
- [ ] Disaster recovery plan documented
- [ ] Monitoring and alerting configured
- [ ] Backup strategy in place
- [ ] Team trained on runbooks
- [ ] All resources tagged properly
- [ ] State backup taken

---

## 📞 Quick Reference

```bash
# Validate before deploying
make validate fmt              # Check code
make security-full             # Check security
make cost-estimate ENV=prod    # Review costs

# Always plan before applying
make plan ENV=prod             # Show changes
make apply ENV=prod            # Deploy (only after approval)

# Monitor after deploying
# Set CloudWatch alarms
# Track costs in Infracost
# Review logs in CloudWatch
```

---

## 🎯 Golden Rules

1. **Infrastructure as Code** - All infrastructure defined in `.tf` files
2. **Version Control** - All changes tracked in git
3. **Test Locally** - Use LocalStack before AWS
4. **Security First** - Scan for vulnerabilities, encrypt everything
5. **Cost Awareness** - Estimate, monitor, optimize
6. **Approval Process** - Plan → Review → Apply
7. **Documentation** - Comment code, maintain runbooks
8. **Automation** - Use Makefile for consistency
9. **Monitoring** - Track metrics, logs, and costs
10. **Disaster Recovery** - Always have backups and recovery plan
