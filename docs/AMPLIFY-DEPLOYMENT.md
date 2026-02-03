# AWS Amplify Deployment Guide

This guide walks you through deploying the renderer and client applications using AWS Amplify.

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Git Repository** (GitHub, GitLab, or Bitbucket) containing your applications
3. **AWS CLI** configured with credentials
4. **Terraform/OpenTofu** installed

## Step 1: Configure Repository Access

### GitHub

1. Go to AWS Amplify Console
2. Navigate to "App settings" > "General"
3. Click "Connect to GitHub"
4. Authorize AWS Amplify to access your repositories

### GitLab/Bitbucket

1. Create a personal access token with repository read access
2. Store the token in AWS Secrets Manager or provide directly

## Step 2: Update Configuration

Edit your `terraform.tfvars` file:

```hcl
# Enable Amplify
enable_amplify = true

# Renderer Configuration
renderer_repository_url = "https://github.com/your-org/paymentform-renderer"
renderer_branch_name    = "main"
renderer_env_vars = {
  NEXT_PUBLIC_API_URL = "https://api.yourdomain.com"
  NODE_ENV            = "production"
}

# Client Configuration
client_repository_url = "https://github.com/your-org/paymentform-client"
client_branch_name    = "main"
client_env_vars = {
  NEXT_PUBLIC_API_URL = "https://api.yourdomain.com"
  NODE_ENV            = "production"
}

# Optional: Custom domains
renderer_custom_domain    = "yourdomain.com"
renderer_subdomain_prefix = "renderer"
client_custom_domain      = "yourdomain.com"
client_subdomain_prefix   = "app"
```

## Step 3: Deploy Infrastructure

```bash
cd /mnt/src/work/apps/paymentform-docker/iaac

# Initialize Terraform
terraform init

# Review changes
terraform plan

# Apply changes
terraform apply
```

## Step 4: Verify Deployment

After successful deployment, get the application URLs:

```bash
terraform output renderer_branch_url
terraform output client_branch_url
```

## Step 5: Configure Custom Domains (Optional)

If you configured custom domains, add DNS records:

### For Renderer

1. Get the Amplify domain from output: `terraform output renderer_default_domain`
2. Create CNAME record:
   - Name: `renderer` (or your subdomain)
   - Value: `<branch>.<amplify-domain>`

### For Client

1. Get the Amplify domain from output: `terraform output client_default_domain`
2. Create CNAME record:
   - Name: `app` (or your subdomain)
   - Value: `<branch>.<amplify-domain>`

## Step 6: Monitor Build Status

### Via AWS Console

1. Go to AWS Amplify Console
2. Select your application (renderer or client)
3. View build logs and deployment status

### Via AWS CLI

```bash
# List Amplify apps
aws amplify list-apps

# Get app details
aws amplify get-app --app-id <app-id>

# List branches
aws amplify list-branches --app-id <app-id>

# Get job details
aws amplify list-jobs --app-id <app-id> --branch-name main
```

## Build Process

### Renderer Build

```bash
# In ../renderer directory
npm ci
npm run build
# Output: .next directory
```

### Client Build

```bash
# In ../client directory
npm ci
npm run build
# Output: .next directory
```

## Troubleshooting

### Build Failures

1. **Check build logs** in Amplify Console
2. **Verify environment variables** are set correctly
3. **Test build locally**:
   ```bash
   cd ../renderer  # or ../client
   npm ci
   npm run build
   ```

### Domain Verification Issues

1. Verify DNS records are correctly configured
2. Wait for DNS propagation (can take up to 48 hours)
3. Check certificate status in Amplify Console

### Missing Dependencies

Ensure `package.json` includes all dependencies:
```json
{
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0"
  }
}
```

## Manual Deployment Trigger

To manually trigger a deployment:

```bash
# Start a new build
aws amplify start-job \
  --app-id <app-id> \
  --branch-name main \
  --job-type RELEASE
```

## Environment-Specific Configuration

### Development

```hcl
environment = "dev"
enable_amplify = false  # Use local development
```

### Sandbox

```hcl
environment = "sandbox"
enable_amplify = true
renderer_branch_name = "develop"
client_branch_name = "develop"
```

### Production

```hcl
environment = "prod"
enable_amplify = true
renderer_branch_name = "main"
client_branch_name = "main"
renderer_custom_domain = "yourdomain.com"
client_custom_domain = "yourdomain.com"
```

## Cost Optimization

1. **Enable build caching** (already configured)
2. **Set up lifecycle policies** for old deployments
3. **Monitor usage** via AWS Cost Explorer
4. **Use branch-based deployments** sparingly

## Security Best Practices

1. **Use environment variables** for sensitive data
2. **Enable HTTPS** (automatic with Amplify)
3. **Configure CSP headers** in Next.js config
4. **Review IAM permissions** regularly
5. **Enable AWS WAF** for additional protection

## CI/CD Integration

### Automatic Deployments

Amplify automatically deploys on:
- Push to configured branch
- Pull request creation (if PR previews enabled)
- Webhook triggers

### Manual Approval

Configure manual approval in `amplify.yml`:

```yaml
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: .next
    files:
      - '**/*'
```

## Rollback

To rollback to a previous deployment:

1. Go to Amplify Console
2. Select the application
3. Choose "Deployments"
4. Select a previous successful deployment
5. Click "Redeploy this version"

## Monitoring and Alerts

Set up CloudWatch alarms for:

```hcl
resource "aws_cloudwatch_metric_alarm" "amplify_build_failures" {
  alarm_name          = "${var.resource_prefix}-amplify-build-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BuildFailureCount"
  namespace           = "AWS/Amplify"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert on Amplify build failures"
}
```

## Clean Up

To remove Amplify resources:

```bash
# Update terraform.tfvars
enable_amplify = false

# Apply changes
terraform apply
```

Or manually delete via console:

```bash
aws amplify delete-app --app-id <app-id>
```

## Additional Resources

- [AWS Amplify Documentation](https://docs.aws.amazon.com/amplify/)
- [Next.js Deployment](https://nextjs.org/docs/deployment)
- [Amplify CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/amplify/)
- [Cost Calculator](https://calculator.aws/)

## Support

For issues or questions:
1. Check Amplify build logs
2. Review this documentation
3. Consult AWS Amplify documentation
4. Contact DevOps team
