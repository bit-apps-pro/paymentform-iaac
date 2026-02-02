# GitHub Workflows Deployment Guide for Submodules

## Overview

Since `backend`, `client`, `renderer`, and `admin` are **git submodules** pointing to separate repositories, each repository needs its own GitHub Actions workflow.

## Submodule Repositories

Based on `.gitmodules`:
- `paymentform-backend` (backend service)
- `paymentform-client` (client dashboard)
- `paymentform-renderer` (multi-tenant renderer)
- `paymentform-admin` (admin panel)

## Workflow Files Location

Workflow files are in: `iaac/docs/github-workflows-for-submodules/`

- `backend-build.yml` → Deploy to `paymentform-backend` repo
- `client-build.yml` → Deploy to `paymentform-client` repo
- `renderer-build.yml` → Deploy to `paymentform-renderer` repo
- `admin-build.yml` → Deploy to `paymentform-admin` repo

## Deployment Instructions

### Step 1: Copy Workflow to Each Submodule Repo

For each submodule, follow these steps:

#### Backend Example

```bash
# Navigate to backend submodule
cd backend

# Create .github/workflows directory
mkdir -p .github/workflows

# Copy the workflow file
cp ../iaac/docs/github-workflows-for-submodules/backend-build.yml .github/workflows/build.yml

# Commit and push
git add .github/workflows/build.yml
git commit -m "Add GitHub Actions workflow for Docker image builds"
git push origin main
```

#### Client Example

```bash
cd client
mkdir -p .github/workflows
cp ../iaac/docs/github-workflows-for-submodules/client-build.yml .github/workflows/build.yml
git add .github/workflows/build.yml
git commit -m "Add GitHub Actions workflow for Docker image builds"
git push origin main
```

#### Renderer Example

```bash
cd renderer
mkdir -p .github/workflows
cp ../iaac/docs/github-workflows-for-submodules/renderer-build.yml .github/workflows/build.yml
git add .github/workflows/build.yml
git commit -m "Add GitHub Actions workflow for Docker image builds"
git push origin main
```

#### Admin Example

```bash
cd admin
mkdir -p .github/workflows
cp ../iaac/docs/github-workflows-for-submodules/admin-build.yml .github/workflows/build.yml
git add .github/workflows/build.yml
git commit -m "Add GitHub Actions workflow for Docker image builds"
git push origin main
```

### Step 2: Verify Dockerfile Exists

Each submodule needs a `Dockerfile` at the root:

```bash
# Check each submodule
ls -la backend/Dockerfile
ls -la client/Dockerfile
ls -la renderer/Dockerfile
ls -la admin/Dockerfile
```

If Dockerfiles don't exist, you may need to:
1. Copy from `.docker/` in the main repo
2. Create new Dockerfiles in each submodule
3. Update the workflow `file:` path if Dockerfile is in a subdirectory

### Step 3: Enable GitHub Actions

For each repository:

1. Go to GitHub repository → **Settings** → **Actions** → **General**
2. Under "Actions permissions", select:
   - ✅ "Allow all actions and reusable workflows"
3. Under "Workflow permissions", select:
   - ✅ "Read and write permissions"
   - ✅ "Allow GitHub Actions to create and approve pull requests"
4. Click **Save**

### Step 4: Test the Workflows

#### Manual Trigger

1. Go to repository → **Actions** tab
2. Select the "Build and Push" workflow
3. Click **Run workflow**
4. Select branch (e.g., `main`)
5. Click **Run workflow**

#### Push Trigger

```bash
# Make a small change
cd backend
echo "# Test" >> README.md
git add README.md
git commit -m "Test GitHub Actions workflow"
git push origin main

# Watch the workflow run in GitHub Actions tab
```

## Workflow Triggers

Each workflow triggers on:

### 1. **Push to Branches**
```yaml
push:
  branches:
    - main
    - develop
    - staging
    - feat/**
```

**When**: Any push to these branches  
**Action**: Builds and pushes image with branch tag  
**Example tags**: `main`, `develop`, `feat-auth`, `main-a1b2c3d`

### 2. **Pull Requests**
```yaml
pull_request:
  branches:
    - main
    - develop
```

**When**: PR opened to main or develop  
**Action**: Builds image but **doesn't push** (test only)  
**Example tags**: `pr-123`

### 3. **Releases** (NEW!)
```yaml
release:
  types: [created, published]
```

**When**: GitHub Release is created or published  
**Action**: Builds and pushes with semantic version tags  
**Example tags**: `v1.2.3`, `1.2`, `1`, `latest`, `stable`

### 4. **Manual Trigger**
```yaml
workflow_dispatch:
```

**When**: Manually triggered from Actions tab  
**Action**: Builds and pushes based on selected branch

## Creating a Release

### Method 1: GitHub UI

1. Go to repository → **Releases** → **Draft a new release**
2. Click "Choose a tag" → Enter version: `v1.0.0`
3. Select or create tag from target: `main`
4. Fill in:
   - **Release title**: `v1.0.0 - Initial Release`
   - **Description**: Release notes
5. Click **Publish release**
6. 🚀 Workflow automatically triggers!

### Method 2: GitHub CLI

```bash
# Create a release
gh release create v1.0.0 \
  --title "v1.0.0 - Initial Release" \
  --notes "First production release" \
  --target main

# List releases
gh release list

# View release details
gh release view v1.0.0
```

### Method 3: Git Tags + GitHub Release

```bash
# Create and push tag
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# Then create release from tag in GitHub UI
# Or use gh CLI
gh release create v1.0.0 --generate-notes
```

## Image Tags Explained

### For Regular Pushes (main branch):
```
ghcr.io/your-org/paymentform-backend:main
ghcr.io/your-org/paymentform-backend:main-a1b2c3d
ghcr.io/your-org/paymentform-backend:latest
```

### For Feature Branches:
```
ghcr.io/your-org/paymentform-backend:feat-auth
ghcr.io/your-org/paymentform-backend:feat-auth-a1b2c3d
```

### For Pull Requests (not pushed):
```
ghcr.io/your-org/paymentform-backend:pr-123
```

### For Releases (v1.2.3):
```
ghcr.io/your-org/paymentform-backend:v1.2.3
ghcr.io/your-org/paymentform-backend:1.2
ghcr.io/your-org/paymentform-backend:1
ghcr.io/your-org/paymentform-backend:latest
ghcr.io/your-org/paymentform-backend:stable
```

**Key Points:**
- `latest` = most recent push to main **OR** most recent release
- `stable` = **only** created on releases
- `v1.2.3` = exact semantic version
- `1.2` = receives updates for patch versions (1.2.0, 1.2.1, etc.)
- `1` = receives updates for minor/patch versions

## Updating Docker Compose for Releases

### Option A: Use Specific Version Tags

```yaml
# docker-compose.yml or docker-compose.prod.yml
services:
  backend:
    image: ghcr.io/your-org/paymentform-backend:v1.0.0
  
  client:
    image: ghcr.io/your-org/paymentform-client:v1.0.0
  
  renderer:
    image: ghcr.io/your-org/paymentform-renderer:v1.0.0
```

### Option B: Use Stable Tag

```yaml
services:
  backend:
    image: ghcr.io/your-org/paymentform-backend:stable
  
  client:
    image: ghcr.io/your-org/paymentform-client:stable
  
  renderer:
    image: ghcr.io/your-org/paymentform-renderer:stable
```

### Option C: Use Environment Variables

```yaml
services:
  backend:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/paymentform-backend:${BACKEND_VERSION:-stable}
  
  client:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/paymentform-client:${CLIENT_VERSION:-stable}
  
  renderer:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/paymentform-renderer:${RENDERER_VERSION:-stable}
```

Then deploy with:

```bash
# For specific versions
export BACKEND_VERSION=v1.0.0
export CLIENT_VERSION=v1.0.0
export RENDERER_VERSION=v1.0.0
docker-compose pull
docker-compose up -d

# For stable
export BACKEND_VERSION=stable
docker-compose pull
docker-compose up -d
```

## Workflow Customization

### Adjust Dockerfile Path

If Dockerfile is not at the root:

```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    file: docker/Dockerfile  # <-- Change this
    push: ${{ github.event_name != 'pull_request' }}
```

### Add Build Arguments

```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    file: Dockerfile
    push: ${{ github.event_name != 'pull_request' }}
    build-args: |
      NODE_ENV=production
      API_VERSION=${{ github.ref_name }}
```

### Add Multi-platform Builds

```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    platforms: linux/amd64,linux/arm64  # <-- Add arm64
    push: ${{ github.event_name != 'pull_request' }}
```

## Verification

### Check Workflow Runs

```bash
# List recent workflow runs
gh run list --repo your-org/paymentform-backend --limit 10

# View specific run
gh run view <run-id> --log

# Watch a running workflow
gh run watch <run-id>
```

### Check Published Images

```bash
# List images in GHCR
gh api /user/packages/container/paymentform-backend/versions

# Or browse: https://github.com/orgs/your-org/packages
```

### Pull and Test

```bash
# Pull the image
docker pull ghcr.io/your-org/paymentform-backend:v1.0.0

# Test run
docker run --rm ghcr.io/your-org/paymentform-backend:v1.0.0 php --version
```

## Troubleshooting

### Workflow Not Triggering on Release

1. Check workflow file is committed to `main` branch
2. Verify Actions are enabled in repository settings
3. Check release was "published" not just created as draft

### Permission Denied When Pushing to GHCR

1. Go to Settings → Actions → General
2. Set Workflow permissions to "Read and write"
3. Re-run the workflow

### Wrong Image Tags

Check `docker/metadata-action` configuration in workflow file. The tagging rules are defined there.

### Release Comment Not Appearing

Ensure workflow has `contents: write` permission or `contents: read` at minimum with the `actions/github-script` action.

## Best Practices

1. **Semantic Versioning**: Use `v1.2.3` format for releases
2. **Changelog**: Include release notes with every release
3. **Testing**: Test in staging before creating production release
4. **Rollback**: Keep previous version tags for easy rollback
5. **Automation**: Consider using release-drafter or semantic-release

## Next Steps

1. Copy workflows to all 4 submodule repos
2. Create initial releases (v0.1.0) for each service
3. Update docker-compose.yml with stable tags
4. Set up release automation (optional)

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Creating Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Semantic Versioning](https://semver.org/)
