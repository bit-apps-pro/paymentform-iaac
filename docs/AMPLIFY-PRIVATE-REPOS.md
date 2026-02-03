# Private Repository Setup for AWS Amplify

## Generate Access Token

### GitHub
```bash
# 1. Go to: https://github.com/settings/tokens/new
# 2. Select scopes:
#    - repo (required for private repos - GitHub doesn't have read-only option)
#    Note: Amplify only needs read access, but GitHub tokens require full repo scope for private repos
# 3. Generate token
# 4. Copy token: ghp_xxxxxxxxxxxxxxxxxxxx
```

### GitLab
```bash
# 1. Go to: https://gitlab.com/-/profile/personal_access_tokens
# 2. Select scopes: read_repository (read-only access)
# 3. Create token
# 4. Copy token: glpat-xxxxxxxxxxxxxxxxxxxx
```

### Bitbucket
```bash
# 1. Go to: https://bitbucket.org/account/settings/app-passwords/
# 2. Select permissions: Repositories (Read only)
# 3. Create password
# 4. Copy password
```

## Configure Terraform

### Option 1: Environment Variable (Recommended)
```bash
export TF_VAR_amplify_access_token="ghp_xxxxxxxxxxxxxxxxxxxx"
```

### Option 2: AWS Secrets Manager
```bash
# Store token
aws secretsmanager create-secret \
  --name amplify-github-token \
  --secret-string "ghp_xxxxxxxxxxxxxxxxxxxx" \
  --region us-east-1

# Reference in terraform.tfvars
amplify_access_token = data.aws_secretsmanager_secret_version.amplify_token.secret_string
```

### Option 3: terraform.tfvars (Not Recommended)
```hcl
amplify_access_token = "ghp_xxxxxxxxxxxxxxxxxxxx"  # Don't commit this!
```

## Deploy

```bash
# With environment variable
export TF_VAR_amplify_access_token="your_token"
cd /mnt/src/work/apps/paymentform-docker/iaac

# Configure
vim terraform.tfvars
# Add:
# enable_amplify = true
# renderer_repository_url = "https://github.com/your-org/private-renderer"
# client_repository_url = "https://github.com/your-org/private-client"

# Deploy
tofu apply
```

## Verify

```bash
# Check Amplify apps created
aws amplify list-apps

# Trigger first build
aws amplify start-job \
  --app-id <renderer-app-id> \
  --branch-name main \
  --job-type RELEASE
```

## Security

- ✅ Token is marked as sensitive in Terraform
- ✅ Not shown in plan/apply output
- ✅ Stored encrypted in state file
- ✅ Amplify only needs read access to repository
- ⚠️ GitHub requires `repo` scope for private repos (no read-only option)
- ⚠️ GitLab/Bitbucket: use `read_repository` scope only
- ⚠️ Never commit token to Git
- ⚠️ Rotate token every 90 days
- ⚠️ Use minimal permissions
