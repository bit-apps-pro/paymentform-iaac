# GitHub Container Registry Setup Guide

This guide covers configuring GitHub Container Registry (GHCR) for hosting Docker images and setting up automated builds.

## What is GHCR?

GitHub Container Registry is a container registry integrated with GitHub:
- **Free tier**: 500MB storage, 1GB transfer/month
- **Pricing**: $0.008/GB storage, $0.50/GB transfer
- **Integration**: Works seamlessly with GitHub Actions
- **Visibility**: Public or private images

## Prerequisites

- GitHub repository for the project
- GitHub account with appropriate permissions
- Docker installed locally (for testing)

## Step 1: Enable GitHub Container Registry

GHCR is enabled by default for all repositories. No setup required!

## Step 2: Create Personal Access Token (PAT)

For pulling images on EC2 instances:

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a descriptive name: `paymentform-ghcr-pull`
4. Select scopes:
   - ✅ `read:packages` (read packages)
   - ✅ `write:packages` (if you need to push manually)
5. Generate token and **copy it immediately**

## Step 3: Store PAT in AWS Secrets Manager

```bash
# Store GitHub PAT for GHCR
aws secretsmanager create-secret \
  --name github-ghcr-token \
  --secret-string "ghp_YOUR_PERSONAL_ACCESS_TOKEN" \
  --region us-east-1

# Verify
aws secretsmanager get-secret-value \
  --secret-id github-ghcr-token \
  --region us-east-1
```

## Step 4: Configure GitHub Actions Workflows

The workflows are already created in `.github/workflows/`:

- `build-backend.yml`
- `build-client.yml`
- `build-renderer.yml`

These workflows automatically:
1. Build Docker images on push to main/develop/staging
2. Tag images with branch name, commit SHA, and semantic version
3. Push to GHCR using `GITHUB_TOKEN` (automatic)

### Enable Workflows

1. Go to your GitHub repository
2. Navigate to Actions tab
3. Enable workflows if prompted
4. Push a commit to trigger the first build

## Step 5: Make Images Public (Optional)

By default, images are private. To make them public:

1. Go to your GitHub profile → Packages
2. Select a package (e.g., `paymentform-backend`)
3. Package settings → Change visibility → Public
4. Confirm

## Step 6: Authenticate Docker on EC2 Instances

### Method 1: Using User Data Script (Automated)

The EC2 user-data script automatically configures GHCR authentication:

```bash
# Included in scripts/traefik-install.sh
mkdir -p /root/.docker
cat > /root/.docker/config.json <<EOF
{
  "auths": {
    "ghcr.io": {
      "auth": "${ghcr_token}"
    }
  }
}
EOF
```

### Method 2: Manual Configuration

SSH into EC2 instance:

```bash
ssh ubuntu@<ec2-ip>

# Get PAT from AWS Secrets Manager
GHCR_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id github-ghcr-token \
  --query SecretString \
  --output text \
  --region us-east-1)

# Login to GHCR
echo $GHCR_TOKEN | docker login ghcr.io -u <your-github-username> --password-stdin

# Verify
docker pull ghcr.io/<your-org>/paymentform-backend:latest
```

## Step 7: Update Docker Compose

Docker Compose is already configured to use GHCR images via environment variables:

```yaml
services:
  backend:
    image: ${GHCR_BACKEND_IMAGE:-ghcr.io/${GITHUB_REPOSITORY_OWNER}/paymentform-backend:${IMAGE_TAG:-latest}}
```

Set environment variables:

```bash
# .env file
GITHUB_REPOSITORY_OWNER=your-org-name
IMAGE_TAG=latest

GHCR_BACKEND_IMAGE=ghcr.io/your-org/paymentform-backend:latest
GHCR_CLIENT_IMAGE=ghcr.io/your-org/paymentform-client:latest
GHCR_RENDERER_IMAGE=ghcr.io/your-org/paymentform-renderer:latest
```

## Step 8: Test Image Builds

### Trigger Manual Build

```bash
# Go to Actions tab in GitHub
# Select a workflow
# Click "Run workflow"
# Select branch
# Run workflow
```

### Monitor Build

```bash
# View workflow runs
gh run list --limit 5

# View specific run logs
gh run view <run-id>
```

### Pull and Test Locally

```bash
# Login to GHCR
echo $GHCR_TOKEN | docker login ghcr.io -u <username> --password-stdin

# Pull image
docker pull ghcr.io/<org>/paymentform-backend:latest

# Test run
docker run --rm ghcr.io/<org>/paymentform-backend:latest php --version
```

## Image Tagging Strategy

Our workflows create multiple tags for each build:

| Tag | Example | Purpose |
|-----|---------|---------|
| `latest` | `latest` | Always points to main branch |
| `branch` | `develop`, `staging` | Latest build for branch |
| `sha` | `main-a1b2c3d` | Specific commit |
| `version` | `v1.2.3` | Semantic version (if tagged) |

Pull specific versions:

```bash
# Latest
docker pull ghcr.io/org/paymentform-backend:latest

# Specific branch
docker pull ghcr.io/org/paymentform-backend:staging

# Specific commit
docker pull ghcr.io/org/paymentform-backend:main-a1b2c3d

# Semantic version
docker pull ghcr.io/org/paymentform-backend:v1.2.3
```

## Managing Images

### List Images

```bash
# Using GitHub CLI
gh api /user/packages/container/paymentform-backend/versions

# Using Docker
docker search ghcr.io/<org>/paymentform
```

### Delete Old Images

1. Go to GitHub → Profile → Packages
2. Select package
3. Package settings → Manage versions
4. Delete old versions

### Automated Cleanup

Add to workflow:

```yaml
- name: Delete old images
  uses: snok/container-retention-policy@v2
  with:
    image-names: paymentform-*
    cut-off: 30 days ago
    keep-at-least: 5
    account-type: org
    org-name: your-org
    token: ${{ secrets.GITHUB_TOKEN }}
```

## Cost Management

### Monitor Usage

1. GitHub → Settings → Billing
2. View packages storage and transfer

### Optimize Costs

1. **Delete unused tags**: Keep only recent tags
2. **Use multi-stage builds**: Reduce image size
3. **Compress layers**: Use COPY instead of ADD
4. **Remove build cache**: In Dockerfiles

Example optimization:

```dockerfile
# Before: 500MB
FROM php:8.2

# After: 150MB
FROM php:8.2-alpine
RUN apk add --no-cache ...
```

## Troubleshooting

### Authentication Failed

```bash
# Check token permissions
gh auth status

# Re-login
echo $GHCR_TOKEN | docker login ghcr.io -u <username> --password-stdin

# Verify token has read:packages scope
```

### Image Not Found

```bash
# Check if image exists
gh api /users/<username>/packages/container/paymentform-backend

# Check image visibility (public/private)

# Verify correct org/username
```

### Build Failures

```bash
# Check workflow logs
gh run view <run-id> --log

# Common issues:
# - Dockerfile path incorrect
# - Missing dependencies
# - Out of memory (use smaller runner)
```

### Pull Rate Limits

GHCR has generous rate limits:
- **Authenticated**: 15,000 requests/hour
- **Unauthenticated**: 1,000 requests/hour

If hitting limits:
- Ensure Docker is authenticated
- Use image caching
- Reduce unnecessary pulls

## Security Best Practices

1. **Use PATs with minimal scopes**: Only `read:packages` for pulling
2. **Rotate tokens regularly**: Every 90 days
3. **Store tokens securely**: AWS Secrets Manager, not in code
4. **Scan images**: Use GitHub's security scanning
5. **Sign images**: Use Docker Content Trust

### Enable Security Scanning

1. Go to repository Settings → Code security
2. Enable:
   - Dependabot alerts
   - Dependabot security updates
   - Code scanning

## Next Steps

- [Cloudflare Setup](./cloudflare-setup.md)
- [Traefik Cloud Setup](./traefik-cloud-setup.md)
- [Complete Deployment](../SANDBOX-DEPLOY.md)

## Resources

- [GHCR Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions Docker](https://docs.github.com/en/actions/publishing-packages/publishing-docker-images)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
