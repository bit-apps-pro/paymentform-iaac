# Secrets Management and Security

## Overview

This document outlines how sensitive data, secrets, and credentials are managed securely across the Payment Form infrastructure.

## Secret Categories

### Application Secrets

- **Laravel App Key**: Application encryption key
- **Database Credentials**: Username and password
- **API Keys**: Third-party service integrations (Razorpay, etc.)
- **JWT Secrets**: Authentication tokens
- **Encryption Keys**: Data encryption keys

### Infrastructure Secrets

- **AWS Access Keys**: For programmatic access (limited use)
- **SSH Keys**: For EC2 access
- **SSL/TLS Certificates**: Domain certificates

### Database Secrets

- **Primary DB Password**: Main database credentials
- **Replica DB Password**: Read replica credentials
- **Backup Encryption Keys**: For backup security

## Storage Solutions

### AWS Secrets Manager (Primary)

Used for application and database secrets.

#### Storing a Secret

```bash
# Store application key
aws secretsmanager create-secret \
  --name paymentform/prod/app-key \
  --description "Laravel application key for production" \
  --secret-string "base64:YOUR_SECRET_KEY_HERE" \
  --tags Key=Environment,Value=prod Key=Component,Value=backend

# Store database credentials
aws secretsmanager create-secret \
  --name paymentform/prod/db-credentials \
  --description "Database credentials" \
  --secret-string '{
    "username": "admin",
    "password": "SECURE_PASSWORD_HERE",
    "engine": "mysql",
    "host": "paymentform-primary.c9akciq32.us-east-1.rds.amazonaws.com",
    "port": 3306,
    "dbname": "paymentform"
  }'
```

#### Retrieving Secrets in Application

```bash
# In Terraform
data "aws_secretsmanager_secret_version" "app_key" {
  secret_id = aws_secretsmanager_secret.app_key.id
}

# In Ansible
- name: Get application secrets
  amazon.aws.aws_secret:
    name: paymentform/{{ environment }}/app-key
  register: app_secret

# In Application Code (Laravel)
$appKey = DB::table('secrets')->where('name', 'app-key')->first()->value;
```

#### Rotating Secrets

```bash
# Enable automatic rotation every 30 days
aws secretsmanager rotate-secret \
  --secret-id paymentform/prod/db-credentials \
  --rotation-rules AutomaticallyAfterDays=30,Duration=3,ScheduleExpression="rate(30 days)"

# Manual rotation
aws secretsmanager rotate-secret \
  --secret-id paymentform/prod/api-keys \
  --rotate-immediately
```

### AWS Systems Manager Parameter Store (Configuration)

Used for non-sensitive configuration values.

```bash
# Store non-sensitive config
aws ssm put-parameter \
  --name /paymentform/prod/config/log-level \
  --value "info" \
  --type "String" \
  --overwrite

# Store sensitive config (encrypted)
aws ssm put-parameter \
  --name /paymentform/prod/config/feature-flags \
  --value '{"new_payment_flow": true}' \
  --type "SecureString" \
  --key-id alias/paymentform
```

### Ansible Vault (Development/Local)

Used for local development and testing.

```bash
# Create vault file
ansible-vault create ansible/vars/secrets.yml

# Edit vault file
ansible-vault edit ansible/vars/secrets.yml

# Run playbook with vault
ansible-playbook playbooks/deploy-backend.yml \
  --ask-vault-pass

# Store vault password in CI/CD
export ANSIBLE_VAULT_PASSWORD_FILE=.vault-pass
```

### .env Files (Local Development Only)

```bash
# .env (NEVER commit to git)
DB_PASSWORD=local_dev_password
RAZORPAY_KEY=test_key_12345
JWT_SECRET=test_secret

# Add to .gitignore
echo ".env" >> .gitignore
echo ".env.local" >> .gitignore
echo ".vault-pass" >> .gitignore
```

## Security Best Practices

### 1. Principle of Least Privilege

- IAM roles have minimal required permissions
- Separate keys for each environment
- Service-specific API keys with limited scope

```bash
# Example IAM policy for backend service
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:paymentform/prod/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::paymentform-prod-storage/*"
    }
  ]
}
```

### 2. Encryption

- Secrets encrypted at rest using KMS
- Encryption in transit using TLS 1.3+
- Database passwords stored encrypted

```bash
# Verify encryption
aws secretsmanager describe-secret \
  --secret-id paymentform/prod/db-credentials \
  --query 'KmsKeyId'
```

### 3. Audit Logging

- All secret access logged to CloudTrail
- Regular audits of access logs
- Alerts on suspicious access patterns

```bash
# Monitor secret access
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --max-results 50

# Set up alert for suspicious access
aws cloudwatch put-metric-alarm \
  --alarm-name suspicious-secret-access \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:alerts
```

### 4. Rotation Policy

- Database passwords: Every 90 days
- API keys: Every 180 days
- Application keys: When infrastructure changes
- SSH keys: Every 1 year

### 5. Secret Sanitization

```bash
# Never log secrets
echo "Do not log: ${DB_PASSWORD}"  # Wrong

# Use masked variables
echo "Connecting to: ${DB_HOST}"  # OK

# Sanitize logs
grep -v "password\|secret\|key" app.log
```

## CI/CD Secret Management

### GitHub Actions Example

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/github-actions-role
          aws-region: us-east-1

      - name: Get secrets
        run: |
          echo "DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id paymentform/prod/db-credentials --query SecretString --output text | jq -r .password)" >> $GITHUB_ENV

      - name: Deploy
        env:
          DB_PASSWORD: ${{ env.DB_PASSWORD }}
        run: |
          ansible-playbook deploy.yml
```

### GitLab CI Example

```yaml
deploy:prod:
  stage: deploy
  environment: production
  script:
    - export DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id paymentform/prod/db-credentials --query SecretString --output text | jq -r .password)
    - ansible-playbook deploy.yml
  only:
    - main
```

## Emergency Access Procedures

### Break-Glass Access

For emergency situations requiring immediate access:

```bash
# Request emergency access (requires approval)
aws iam assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/emergency-access-role \
  --role-session-name emergency-session-$(date +%s)

# Access is logged and audited
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=AssumedRoleArn,AttributeValue=arn:aws:iam::ACCOUNT:role/emergency-access-role
```

### Manual Secret Retrieval (Last Resort)

1. Get approval from on-call SRE and VP Engineering
2. Retrieve secret from Secrets Manager
3. Document access in ticket
4. Rotate secret within 24 hours
5. Review audit logs

## Regular Maintenance

### Weekly

- [ ] Review failed secret access attempts
- [ ] Verify secret rotation status

### Monthly

- [ ] Audit active API keys
- [ ] Review IAM permissions
- [ ] Verify encryption status

### Quarterly

- [ ] Full secrets audit
- [ ] Test secret recovery procedures
- [ ] Update documentation

---

**Last Updated**: 2026-01-20
**Next Review**: 2026-04-20
