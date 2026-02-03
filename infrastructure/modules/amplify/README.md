# AWS Amplify Module

This module provisions AWS Amplify applications for the renderer and client Next.js projects.

## Overview

AWS Amplify provides a fully managed hosting solution for static and server-side rendered applications with:
- Automatic builds and deployments from Git repositories
- Built-in CI/CD pipeline
- Global CDN distribution
- SSL/TLS certificates
- Environment variable management
- Branch-based deployments

## Features

- **Dual Application Support**: Provisions separate Amplify apps for renderer and client
- **Next.js Optimized**: Pre-configured build settings for Next.js applications
- **Custom Domains**: Optional custom domain configuration
- **Environment Variables**: Secure environment variable management
- **Branch Management**: Automatic branch detection and deployment
- **Build Caching**: Node modules caching for faster builds

## Usage

### Basic Configuration

```hcl
module "amplify" {
  source = "./modules/amplify"

  resource_prefix = "paymentform-prod"
  environment     = "prod"
  standard_tags   = local.standard_tags

  # Renderer configuration
  renderer_repository_url = "https://github.com/your-org/renderer"
  renderer_branch_name    = "main"
  renderer_env_vars = {
    NEXT_PUBLIC_API_URL = "https://api.yourdomain.com"
    NODE_ENV            = "production"
  }

  # Client configuration
  client_repository_url = "https://github.com/your-org/client"
  client_branch_name    = "main"
  client_env_vars = {
    NEXT_PUBLIC_API_URL = "https://api.yourdomain.com"
    NODE_ENV            = "production"
  }
}
```

### With Custom Domains

```hcl
module "amplify" {
  source = "./modules/amplify"

  resource_prefix = "paymentform-prod"
  environment     = "prod"
  standard_tags   = local.standard_tags

  # Renderer with custom domain
  renderer_repository_url   = "https://github.com/your-org/renderer"
  renderer_custom_domain    = "yourdomain.com"
  renderer_subdomain_prefix = "renderer"  # Will create renderer.yourdomain.com

  # Client with custom domain
  client_repository_url   = "https://github.com/your-org/client"
  client_custom_domain    = "yourdomain.com"
  client_subdomain_prefix = "app"  # Will create app.yourdomain.com
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| resource_prefix | Prefix for resource naming | `string` | - | yes |
| environment | Environment name (dev, staging, prod) | `string` | - | yes |
| standard_tags | Standard tags to apply to all resources | `map(string)` | `{}` | no |
| renderer_repository_url | Git repository URL for renderer | `string` | - | yes |
| renderer_branch_name | Branch name for renderer | `string` | `"main"` | no |
| renderer_env_vars | Environment variables for renderer | `map(string)` | `{}` | no |
| renderer_custom_domain | Custom domain for renderer | `string` | `""` | no |
| renderer_subdomain_prefix | Subdomain prefix for renderer | `string` | `""` | no |
| client_repository_url | Git repository URL for client | `string` | - | yes |
| client_branch_name | Branch name for client | `string` | `"main"` | no |
| client_env_vars | Environment variables for client | `map(string)` | `{}` | no |
| client_custom_domain | Custom domain for client | `string` | `""` | no |
| client_subdomain_prefix | Subdomain prefix for client | `string` | `""` | no |
| enable_auto_branch_creation | Enable automatic branch creation | `bool` | `false` | no |
| enable_branch_auto_build | Enable automatic builds for branches | `bool` | `true` | no |
| enable_branch_auto_deletion | Enable automatic branch deletion | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| renderer_app_id | Amplify app ID for renderer |
| renderer_app_arn | Amplify app ARN for renderer |
| renderer_default_domain | Default Amplify domain for renderer |
| renderer_branch_url | URL for renderer branch |
| renderer_custom_domain_url | Custom domain URL for renderer |
| client_app_id | Amplify app ID for client |
| client_app_arn | Amplify app ARN for client |
| client_default_domain | Default Amplify domain for client |
| client_branch_url | URL for client branch |
| client_custom_domain_url | Custom domain URL for client |

## Build Configuration

The module uses Next.js-optimized build settings:

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
  cache:
    paths:
      - node_modules/**/*
```

## Repository Setup

### GitHub

1. Connect your GitHub repository to AWS Amplify
2. Grant Amplify access to your repository
3. Configure webhook for automatic deployments

### GitLab/Bitbucket

Similar setup process with OAuth or access token authentication.

## Custom Domain Setup

1. Add custom domain in Amplify console or via this module
2. Create DNS records (CNAME or ALIAS) pointing to Amplify domain
3. Wait for SSL certificate provisioning (~15 minutes)
4. Verify domain ownership

## Environment Variables

Environment variables can be configured per application:

```hcl
renderer_env_vars = {
  NEXT_PUBLIC_API_URL        = "https://api.yourdomain.com"
  NEXT_PUBLIC_ENVIRONMENT    = "production"
  NODE_ENV                   = "production"
  NEXT_TELEMETRY_DISABLED    = "1"
}
```

## Cost Considerations

- **Build Minutes**: First 1000 build minutes/month free, then $0.01/minute
- **Hosting**: First 15 GB served/month free, then $0.15/GB
- **Storage**: First 5 GB free, then $0.023/GB/month
- **Custom Domains**: Free

Typical monthly cost for small-medium projects: $0-10

## Notes

- Amplify automatically provisions and renews SSL certificates
- Build cache significantly speeds up subsequent deployments
- Each branch can have its own deployment and URL
- Supports monorepo and multi-app repositories
- Automatic PR previews can be enabled

## Documentation

- [AWS Amplify Documentation](https://docs.aws.amazon.com/amplify/)
- [Next.js on Amplify](https://docs.aws.amazon.com/amplify/latest/userguide/server-side-rendering-amplify.html)
