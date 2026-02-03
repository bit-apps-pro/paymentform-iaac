# AWS Amplify Integration Summary

## Overview

AWS Amplify has been successfully integrated into the infrastructure for deploying the **renderer** and **client** Next.js applications using build-based deployment.

## What Was Added

### 1. Amplify Module (`infrastructure/modules/amplify/`)

New Terraform module that provisions:
- AWS Amplify applications for renderer and client
- Branch-based deployments
- Custom domain configuration (optional)
- Environment variable management
- Automatic build and deployment pipeline

**Files:**
- `main.tf` - Resource definitions for Amplify apps
- `variables.tf` - Module input variables
- `outputs.tf` - Module outputs (URLs, app IDs)
- `README.md` - Module documentation

### 2. Infrastructure Integration

**Modified Files:**
- `infrastructure/main.tf` - Added Amplify module integration
- `infrastructure/variables.tf` - Added Amplify configuration variables
- `infrastructure/outputs.tf` - Added Amplify outputs

**Configuration Variables:**
```hcl
enable_amplify              # Toggle Amplify on/off
renderer_repository_url     # Git repo URL for renderer
renderer_branch_name        # Branch to deploy (default: main)
renderer_env_vars           # Environment variables map
renderer_custom_domain      # Optional custom domain
client_repository_url       # Git repo URL for client
client_branch_name          # Branch to deploy (default: main)
client_env_vars             # Environment variables map
client_custom_domain        # Optional custom domain
```

### 3. Documentation

- `docs/AMPLIFY-DEPLOYMENT.md` - Complete deployment guide
- `infrastructure/modules/amplify/README.md` - Module reference
- `terraform.tfvars.example` - Updated with Amplify examples

## Quick Start

### 1. Configure in `terraform.tfvars`

```hcl
# Enable Amplify
enable_amplify = true

# Renderer (from ../renderer) - PRIVATE REPO
renderer_repository_url = "https://github.com/your-org/paymentform-renderer"
renderer_branch_name    = "main"
renderer_env_vars = {
  NEXT_PUBLIC_API_URL = "https://api.yourdomain.com"
  NODE_ENV            = "production"
}

# Client (from ../client) - PRIVATE REPO
client_repository_url = "https://github.com/your-org/paymentform-client"
client_branch_name    = "main"
client_env_vars = {
  NEXT_PUBLIC_API_URL = "https://api.yourdomain.com"
  NODE_ENV            = "production"
}

# Access token for private repositories
amplify_access_token = ""  # Set via environment variable
```

### 2. Set Access Token (For Private Repos)

```bash
# Generate token: https://github.com/settings/tokens/new
# Scopes: repo (required for private repos - read-only not available)

export TF_VAR_amplify_access_token="ghp_xxxxxxxxxxxxxxxxxxxx"
```

### 2. Deploy

```bash
cd /mnt/src/work/apps/paymentform-docker/iaac

# Initialize (first time only)
terraform init

# Deploy
terraform apply
```

### 3. Get URLs

```bash
terraform output renderer_branch_url
terraform output client_branch_url
```

## Build Configuration

The module is pre-configured for Next.js builds:

```yaml
# Automatically runs for each deployment
npm ci              # Install dependencies
npm run build       # Build Next.js app
# Deploy .next/*    # Deploy build artifacts
```

## Project Paths

- **Renderer**: `/mnt/src/work/apps/paymentform-docker/renderer`
- **Client**: `/mnt/src/work/apps/paymentform-docker/client`
- **IaaC**: `/mnt/src/work/apps/paymentform-docker/iaac`

## Features

✅ Automatic builds on git push  
✅ SSL/TLS certificates (automatic)  
✅ Global CDN distribution  
✅ Environment variable management  
✅ Branch-based deployments  
✅ Custom domain support  
✅ Build caching for faster deployments  
✅ Zero-downtime deployments  

## Cost Estimate

**Free Tier:**
- 1000 build minutes/month
- 15 GB data transfer/month
- 5 GB storage

**Typical Monthly Cost:** $0-10 for small-medium projects

## Key Outputs

| Output | Description |
|--------|-------------|
| `renderer_branch_url` | Live URL for renderer app |
| `client_branch_url` | Live URL for client app |
| `renderer_app_id` | Amplify app ID for renderer |
| `client_app_id` | Amplify app ID for client |
| `*_custom_domain_url` | Custom domain URL (if configured) |

## Next Steps

1. **Configure Git Repository Access** in AWS Amplify Console
2. **Set up environment variables** in `terraform.tfvars`
3. **Deploy infrastructure** with `terraform apply`
4. **Configure custom domains** (optional)
5. **Monitor builds** in AWS Amplify Console

## Additional Configuration Options

### Custom Domain

```hcl
renderer_custom_domain    = "yourdomain.com"
renderer_subdomain_prefix = "renderer"  # Creates renderer.yourdomain.com
```

### Different Branches

```hcl
# Deploy from develop branch for sandbox
renderer_branch_name = "develop"
client_branch_name   = "develop"
```

### Additional Environment Variables

```hcl
renderer_env_vars = {
  NEXT_PUBLIC_API_URL        = "https://api.yourdomain.com"
  NEXT_PUBLIC_ENVIRONMENT    = "production"
  NODE_ENV                   = "production"
  NEXT_TELEMETRY_DISABLED    = "1"
}
```

## Monitoring

Access build logs and deployment status:
- AWS Console: Amplify > Your App > Deployments
- AWS CLI: `aws amplify list-jobs --app-id <app-id> --branch-name main`

## Security

- ✅ HTTPS enforced automatically
- ✅ Environment variables encrypted
- ✅ IAM-based access control
- ✅ VPC connectivity (optional)
- ✅ AWS WAF integration (optional)

## Troubleshooting

### Build Fails

1. Check build logs in Amplify Console
2. Test locally: `cd ../renderer && npm ci && npm run build`
3. Verify environment variables are correct

### Domain Not Working

1. Verify DNS records point to Amplify
2. Wait for DNS propagation (up to 48 hours)
3. Check SSL certificate status

## Documentation Links

- [Full Deployment Guide](./docs/AMPLIFY-DEPLOYMENT.md)
- [Module README](./infrastructure/modules/amplify/README.md)
- [AWS Amplify Docs](https://docs.aws.amazon.com/amplify/)

## Support

For issues:
1. Review build logs in AWS Console
2. Check documentation
3. Test builds locally
4. Contact DevOps team

---

**Status**: ✅ Ready for deployment  
**Last Updated**: 2026-02-03
