# Cost Estimation Guide - Count Cost Before Deployment

## 🚀 Quick Start (2 Commands)

```bash
# 1. Install Infracost (one-time)
make install-tools

# 2. Estimate costs
make cost-estimate ENV=prod
```

---

## 📊 Cost Estimation Commands

### Estimate Single Environment

```bash
# DEV environment
make cost-estimate ENV=dev

# STAGING environment
make cost-estimate ENV=staging

# PRODUCTION environment
make cost-estimate ENV=prod
```

**Output:** Shows estimated monthly costs in table format

### Estimate All Environments

```bash
make cost-estimate-all
```

**Output:** Three separate cost breakdowns:

- dev: estimated monthly cost
- staging: estimated monthly cost
- prod: estimated monthly cost

---

## 📈 Understanding Cost Output

### Table Format Output

```
┌────────────────────────────────────────────────────┐
│ Monthly Cost Estimate                              │
├────────────────────────────────────────────────────┤
│ Resource Type      │ Count │ Cost/Month            │
├────────────────────────────────────────────────────┤
│ EC2 Instance       │ 1     │ $8.50                 │
│ RDS Database       │ 1     │ $35.00                │
│ S3 Storage         │ 50GB  │ $1.15                 │
│ ALB               │ 1     │ $16.00                │
├────────────────────────────────────────────────────┤
│ TOTAL MONTHLY      │       │ $60.65                │
└────────────────────────────────────────────────────┘
```

### Cost Report (JSON)

```bash
# View as JSON
cat cost-estimate-prod.json

# Pretty print
jq . cost-estimate-prod.json

# View just the total
jq '.totalMonthlyCost' cost-estimate-prod.json
# Output: 2889.50

# View costs by resource
jq '.resources[] | {name: .name, monthly: .costPerMonth}' cost-estimate-prod.json
```

---

## 🔍 Detailed Cost Analysis

### View Total Monthly Cost

```bash
# Single environment
jq '.totalMonthlyCost' cost-estimate-prod.json
# Output: 2889.50 (means $2,889.50/month)

# All environments
echo "DEV:" && jq '.totalMonthlyCost' cost-estimate-dev.json
echo "STAGING:" && jq '.totalMonthlyCost' cost-estimate-staging.json
echo "PROD:" && jq '.totalMonthlyCost' cost-estimate-prod.json
```

### View Cost by Service

```bash
# Show resource name and cost
jq '.resources[] | {name: .name, resourceType: .resourceType, cost: .costPerMonth}' cost-estimate-prod.json

# Example output:
# {
#   "name": "api_server_prod",
#   "resourceType": "aws_instance",
#   "cost": 96.00
# }
```

### Calculate Annual Cost

```bash
# Convert monthly to annual
jq '.totalMonthlyCost * 12' cost-estimate-prod.json
# Output: 34674 (means $34,674/year)

# View annual costs for all resources
jq '.resources[] | {name: .name, monthly: .costPerMonth, annual: (.costPerMonth * 12)}' cost-estimate-prod.json
```

### Find Most Expensive Resources

```bash
# Sort by cost (highest first)
jq '.resources[] | {name: .name, cost: .costPerMonth}' cost-estimate-prod.json | \
  jq -s 'sort_by(.cost) | reverse | .[0:5]'
# Shows top 5 most expensive resources
```

---

## 💰 Comparing Costs Across Environments

### Side-by-Side Comparison

```bash
# Get costs for all environments
DEV=$(jq '.totalMonthlyCost' cost-estimate-dev.json)
STAGING=$(jq '.totalMonthlyCost' cost-estimate-staging.json)
PROD=$(jq '.totalMonthlyCost' cost-estimate-prod.json)

echo "DEV: \$$DEV/month"
echo "STAGING: \$$STAGING/month"
echo "PROD: \$$PROD/month"
echo ""
echo "Annual Costs:"
echo "DEV: \$$(echo "$DEV * 12" | bc)"
echo "STAGING: \$$(echo "$STAGING * 12" | bc)"
echo "PROD: \$$(echo "$PROD * 12" | bc)"
```

### Calculate Environment Ratio

```bash
# How much more expensive is prod vs dev?
jq -r '"Prod is " + (.totalMonthlyCost / 50) + "x more expensive than Dev"' cost-estimate-prod.json
# Example: "Prod is 60x more expensive than Dev"
```

---

## 🎯 Cost Breakdown Examples

### Development Environment Typical Costs

```
Resource              Quantity  Unit Cost    Monthly Total
─────────────────────────────────────────────────────────
EC2 (t3.micro)       1         $8.50        $8.50
RDS (db.t3.micro)    1         $35.00       $35.00
S3 Storage (50GB)    1         $1.15        $1.15
CloudWatch Logs      varies    $0.50        $0.50
─────────────────────────────────────────────────────────
TOTAL                                       $45.15/month
ANNUAL                                      $541.80/year
```

### Production Environment Typical Costs

```
Resource              Quantity  Unit Cost    Monthly Total
─────────────────────────────────────────────────────────
EC2 (m5.large)       3         $96.00       $288.00
RDS (db.m5.large)    2         $600.00      $1,200.00
ALB                  1         $16.00       $16.00
NAT Gateway          1         $32.00       $32.00
CloudFront           100GB      $0.085/GB    $50.00
S3 Storage (1TB)     1          $23.00       $23.00
CloudWatch Logs      varies    $2.00        $2.00
─────────────────────────────────────────────────────────
TOTAL                                       $1,611.00/month
ANNUAL                                      $19,332/year
```

---

## 📋 Pre-Deployment Cost Review Checklist

Before deploying to production, check costs:

```bash
# Step 1: Run full cost estimation
make cost-estimate-all

# Step 2: View production costs
echo "=== PRODUCTION COSTS ==="
jq '.totalMonthlyCost' cost-estimate-prod.json
echo ""

# Step 3: View top 10 most expensive resources
echo "=== TOP EXPENSIVE RESOURCES ==="
jq '.resources[] | {name: .name, monthly: .costPerMonth}' cost-estimate-prod.json | \
  jq -s 'sort_by(.monthly) | reverse | .[0:10]' | \
  jq '.[] | "\(.name): $\(.monthly)/month"' -r

# Step 4: Calculate annual cost
echo ""
echo "=== ANNUAL COST ==="
jq '.totalMonthlyCost * 12' cost-estimate-prod.json

# Step 5: Get approval before proceeding
echo ""
echo "AWAITING APPROVAL FROM FINANCE/MANAGEMENT"
echo "Press Enter to continue with deployment..."
read approval
```

---

## 🔧 Detailed Cost Estimation Workflow

### Workflow Step-by-Step

#### 1. Make Infrastructure Changes

```hcl
# infrastructure/environments/prod/terraform.tfvars
resource "aws_db_instance" "main" {
  allocated_storage = 100  # Changed from 50GB
  instance_class = "db.m5.large"  # Changed from db.t3.large
}
```

#### 2. Estimate New Costs

```bash
make cost-estimate ENV=prod
```

#### 3. Review the Output

```
Monthly Cost Estimate:
Resource                    Old Cost    New Cost    Change
────────────────────────────────────────────────────────
RDS Database               $1,000      $1,200      +$200
────────────────────────────────────────────────────────
TOTAL                      $1,400      $1,600      +$200/month = +$2,400/year
```

#### 4. Compare with Budget

```bash
# Does this fit within your $2,000/month budget?
MONTHLY_COST=$(jq '.totalMonthlyCost' cost-estimate-prod.json)
BUDGET=2000

if (( $(echo "$MONTHLY_COST > $BUDGET" | bc -l) )); then
  echo "❌ COST EXCEEDS BUDGET: $MONTHLY_COST > $BUDGET"
  echo "Optimize infrastructure before deployment"
  exit 1
else
  echo "✅ COST WITHIN BUDGET: $MONTHLY_COST <= $BUDGET"
  echo "Proceed with deployment"
fi
```

#### 5. Optimize if Needed

If costs are too high, make adjustments:

```hcl
# Option 1: Use smaller instance
instance_class = "db.m5.large"  # Change to db.t3.large

# Option 2: Use reserved instances (30-60% savings)
# Update purchasing option in infrastructure code

# Option 3: Remove unnecessary resources
# Comment out or delete unused resources
```

#### 6. Re-estimate After Changes

```bash
make cost-estimate ENV=prod
# Verify costs are now acceptable
```

#### 7. Deploy with Confidence

```bash
make plan ENV=prod
make apply ENV=prod
```

---

## 💡 Cost Optimization Tips

### Before You Deploy

**1. Check for Expensive Resources**

```bash
# Find resources costing more than $100/month
jq '.resources[] | select(.costPerMonth > 100) | {name: .name, cost: .costPerMonth}' cost-estimate-prod.json
```

**2. Compare Instance Types**

```bash
# View current instance configuration
grep "instance_type" infrastructure/environments/prod/terraform.tfvars

# Research cheaper alternatives
# t3.large: $61/month
# t3.medium: $32/month
# t3.small: $16/month
```

**3. Check Database Size**

```bash
# View allocated storage
grep "allocated_storage" infrastructure/environments/prod/terraform.tfvars

# Consider: Do you really need 500GB?
# Start smaller, scale up as needed
```

**4. Review Backup Retention**

```hcl
# Shorter retention = lower cost
backup_retention_period = 7   # 7 days instead of 30
# Saves approximately $5-10/month per database
```

### Cost Reduction Strategies

| Strategy                             | Savings | Impact                      |
| ------------------------------------ | ------- | --------------------------- |
| Use Reserved Instances (1-year)      | 30%     | Dev/Staging not affected    |
| Use Reserved Instances (3-year)      | 60%     | Dev/Staging not affected    |
| Use Spot Instances                   | 70-90%  | Acceptable for non-critical |
| Right-size instances                 | 20-50%  | May need capacity testing   |
| Reduce backup retention              | 10-20%  | Less recovery history       |
| Schedule resources (nights/weekends) | 50%     | Dev/Staging only            |
| Use cheaper storage classes          | 5-30%   | Depends on access patterns  |

---

## 📊 Cost Monitoring Automation

### Create a Cost Alert Script

```bash
#!/bin/bash
# cost-alert.sh - Alert if costs exceed threshold

THRESHOLD=2000  # $2,000/month
ENVIRONMENT="prod"

MONTHLY_COST=$(jq '.totalMonthlyCost' cost-estimate-${ENVIRONMENT}.json)

if (( $(echo "$MONTHLY_COST > $THRESHOLD" | bc -l) )); then
  echo "⚠️  ALERT: ${ENVIRONMENT} costs ($MONTHLY_COST) exceed threshold ($THRESHOLD)"
  # Send email/Slack notification
  curl -X POST https://hooks.slack.com/... -d "Cost Alert: $MONTHLY_COST"
else
  echo "✅ Costs are within budget"
fi
```

### Schedule Regular Cost Checks

```bash
# Add to crontab (check costs weekly)
0 9 * * 1 cd /path/to/iaac && make cost-estimate-all >> /var/log/cost-check.log

# Check costs manually anytime
make cost-estimate-all
```

---

## 🎓 Understanding Cost Components

### EC2 Instances

```
Hourly Rate Calculation:
- t3.micro: $0.0104/hour = $7.56/month (730 hours)
- t3.small: $0.0208/hour = $15.18/month
- m5.large: $0.096/hour = $70.08/month
- m5.xlarge: $0.192/hour = $140.16/month
```

### RDS Databases

```
Monthly Cost = Instance Rate + Storage + Backup Storage
- db.t3.micro: $0.015/hour = $35/month (730 hours)
- db.t3.small: $0.029/hour = $70/month
- db.m5.large: $0.29/hour = $600/month
- Storage: $0.23/GB/month (100GB = $23)
- Backup Storage: $0.095/GB/month
```

### S3 Storage

```
Monthly Cost by Storage Class:
- Standard: $0.023/GB (first 50TB)
- Standard-IA: $0.0125/GB (infrequent access)
- Glacier: $0.004/GB (archive)
- Deep Archive: $0.00099/GB (long-term archive)

Example: 1TB (1024GB)
- Standard: $23.55/month
- Glacier: $4.10/month
- Deep Archive: $1.01/month
```

---

## ✅ Cost Estimation Best Practices

1. **Always estimate before deploying** - Avoid surprises
2. **Review costs with stakeholders** - Get approval
3. **Compare environments** - Understand scaling
4. **Track over time** - Monitor for cost creep
5. **Document changes** - Note why costs changed
6. **Optimize regularly** - Review and improve
7. **Use cost allocation tags** - Track by project/team
8. **Set up alerts** - Be notified of anomalies

---

## 🚀 Complete Cost Review Process

```bash
#!/bin/bash
# complete-cost-review.sh

echo "🚀 COMPLETE COST REVIEW PROCESS"
echo "================================="
echo ""

# Step 1: Install tools
echo "Step 1: Installing tools..."
make install-tools
echo "✅ Tools installed"
echo ""

# Step 2: Estimate all environments
echo "Step 2: Estimating costs for all environments..."
make cost-estimate-all
echo "✅ Cost estimates generated"
echo ""

# Step 3: Show comparison
echo "Step 3: Cost Comparison"
echo "─────────────────────"
echo -n "DEV: $"
jq '.totalMonthlyCost' cost-estimate-dev.json
echo -n "STAGING: $"
jq '.totalMonthlyCost' cost-estimate-staging.json
echo -n "PROD: $"
jq '.totalMonthlyCost' cost-estimate-prod.json
echo ""

# Step 4: Show annual costs
echo "Step 4: Annual Costs"
echo "──────────────────"
echo -n "DEV: $"
jq '.totalMonthlyCost * 12' cost-estimate-dev.json
echo -n "STAGING: $"
jq '.totalMonthlyCost * 12' cost-estimate-staging.json
echo -n "PROD: $"
jq '.totalMonthlyCost * 12' cost-estimate-prod.json
echo ""

# Step 5: Show top expensive resources (PROD)
echo "Step 5: Top 5 Most Expensive Resources (PROD)"
echo "───────────────────────────────────────────"
jq '.resources[] | {name: .name, cost: .costPerMonth}' cost-estimate-prod.json | \
  jq -s 'sort_by(.cost) | reverse | .[0:5] | .[] | "\(.name): $\(.cost)/month"' -r
echo ""

echo "✅ Cost review complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Review cost-estimate-*.json files"
echo "2. Identify optimization opportunities"
echo "3. Get stakeholder approval"
echo "4. Deploy when approved"
```

---

## 📞 Quick Commands Reference

```bash
# Estimate specific environment
make cost-estimate ENV=dev
make cost-estimate ENV=staging
make cost-estimate ENV=prod

# Estimate all at once
make cost-estimate-all

# View production costs
jq '.totalMonthlyCost' cost-estimate-prod.json

# View annual projection
jq '.totalMonthlyCost * 12' cost-estimate-prod.json

# Find most expensive resource
jq '.resources | max_by(.costPerMonth) | {name: .name, cost: .costPerMonth}' cost-estimate-prod.json

# Count resources by type
jq '.resources[] | .resourceType' cost-estimate-prod.json | sort | uniq -c

# Export to CSV for reporting
jq -r '.resources[] | [.name, .resourceType, .costPerMonth] | @csv' cost-estimate-prod.json > costs.csv
```

---

## 🎯 Cost Estimation Checklist

Before production deployment:

- [ ] Run `make cost-estimate ENV=prod`
- [ ] Review total monthly cost
- [ ] Review annual projection
- [ ] Identify most expensive resources
- [ ] Check for optimization opportunities
- [ ] Compare with approved budget
- [ ] Get Finance/Management approval
- [ ] Document cost assumptions
- [ ] Set up cost alerts
- [ ] Proceed with deployment
