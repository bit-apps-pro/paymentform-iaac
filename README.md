# Infrastructure as Code - PaymentForm

OpenTofu/Terraform infrastructure with AWS backend, Cloudflare Containers for client/renderer, and Cloudflare R2 for storage.

## Quick Start

```bash
# 1. Navigate to environment
cd environments/sandbox

# 2. Set environment variables
cp ../../.envrc.example .envrc
# Edit .envrc with your secrets
source .envrc

# 3. Deploy
tofu init && tofu plan -out=tfplan && tofu apply tfplan
```

## Structure

```
iaac/
├── providers/              # Cloud provider modules
│   ├── aws/
│   │   ├── compute/       # EC2 backend
│   │   ├── networking/    # VPC, subnets
│   │   ├── security/      # Security groups
│   │   └── ssm/           # Secrets management
│   └── cloudflare/
│       ├── containers/    # Reusable container module
│       ├── dns/           # DNS, WAF, rate limiting
│       ├── r2/            # R2 buckets + SSL config
│       └── kv/            # KV namespaces
│
├── environments/           # Environment-specific configs
│   ├── dev/
│   ├── sandbox/
│   │   ├── main.tf        # Calls providers/
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│
├── modules/                # (Optional) Custom composed modules
│
├── .envrc.example          # Environment variables template
└── terraform.tfvars.example
```

## Architecture

```
┌─────────────────┐                        ┌─────────────────────────────┐
│   Cloudflare    │                        │      Cloudflare             │
│      DNS        │                        │       Containers            │
│                 │                        │                             │
│  - api.*        │───────┐                │  ┌───────────────────────┐  │
│  - app.*        │───┐   │                │  │  Client Container     │  │
│  - *.renderer.* │───┼───┼────────────────│  │  (Next.js SSR)        │  │
└─────────────────┘   │   │                │  └───────────────────────┘  │
                      │   │                │  ┌───────────────────────┐  │
                      │   └────────────────│  │  Renderer Container   │  │
                      │                    │  │  (Next.js + Caddy)    │  │
                      │                    │  └───────────────────────┘  │
                      │                    └─────────────────────────────┘
                      │                                    ▲
┌─────────────────┐   │                                    │
│      AWS        │   │  ┌──────────────────────────────┐  │
│   (Backend)     │   │  │       Cloudflare R2          │  │
│                 │   │  │  - Application Storage       │  │
│  ┌───────────┐  │◄──┴──│  - SSL Config Bucket         │  │
│  │   EC2     │  │      └──────────────────────────────┘  │
│  │  (API)    │◄──────────────────────────────────────────┘
│  └───────────┘  │
│  ┌───────────┐  │      ┌──────────────────────────────┐
│  │   SSM     │◄─┘      │       Cloudflare KV          │
│  │  Secrets  │         │  - Tenants Namespace         │
│  └───────────┘         └──────────────────────────────┘
└─────────────────┘
```

## Key Features

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Client** | Cloudflare Containers | Next.js SSR dashboard |
| **Renderer** | Cloudflare Containers | Next.js + Caddy for wildcard TLS |
| **Backend** | AWS EC2 | Laravel/FrankenPHP API |
| **Storage** | Cloudflare R2 | File uploads + SSL cert persistence |
| **Secrets** | AWS SSM | 16 encrypted parameters |
| **KV Store** | Cloudflare KV | Tenant session/state storage |

## Prerequisites

- OpenTofu/Terraform >= 1.8
- AWS CLI configured
- Cloudflare API token (permissions: Workers Scripts/Routes, Container Registry, R2, DNS)

## Required Variables

```bash
# Cloudflare
export TF_VAR_cloudflare_api_token="..."
export TF_VAR_cloudflare_account_id="..."
export TF_VAR_cloudflare_zone_id="..."

# Containers
export TF_VAR_client_container_image="ghcr.io/org/client:latest"
export TF_VAR_renderer_container_image="ghcr.io/org/renderer:latest"
export TF_VAR_ghcr_token="..."

# R2 SSL Config
export TF_VAR_r2_ssl_access_key_id="..."
export TF_VAR_r2_ssl_secret_access_key="..."

# Database
export TF_VAR_neon_database_url="..."
export TF_VAR_turso_api_token="..."
```

See `.envrc.example` for full list.

## Container Images

**Client (Next.js SSR):**
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY .next/standalone ./
COPY .next/static ./.next/static
EXPOSE 3000
CMD ["node", "server.js"]
```

**Renderer (Next.js + Caddy):**
```dockerfile
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=client /app/.next/standalone /srv/app
EXPOSE 443
```

## R2 SSL Config

Renderer stores Caddy certificates in R2 for persistence across restarts:

```bash
R2_SSL_BUCKET_NAME=sandbox-paymentform-ssl-config
R2_SSL_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_SSL_ACCESS_KEY_ID=...
R2_SSL_SECRET_ACCESS_KEY=...
```

## Cost Estimate

| Resource | Before | After | Savings |
|----------|--------|-------|---------|
| AWS Amplify | $0-25/mo | $0 | $0-25/mo |
| EC2 Renderer | ~$15/mo | $0 | ~$15/mo |
| Cloudflare Containers | $0 | ~$10-15/mo | -$10-15/mo |
| R2 SSL Storage | $0 | <$1/mo | <$1/mo |
| **Total** | **~$15-40/mo** | **~$10-16/mo** | **~$5-24/mo** |

**Additional:** AWS Backend EC2 (~$15-30/mo), Neon DB (~$0-19/mo)

## Migration from Amplify/EC2

1. Build and push container images to GHCR
2. Deploy with `enable_cloudflare_containers = true`
3. Test containers (run parallel to existing infra)
4. Update DNS to point to containers
5. Decommission Amplify apps and renderer EC2

## Documentation

- `terraform.tfvars.example` - Variable examples
- `.envrc.example` - Environment variables template

## Support

Check provider directories (`providers/aws/*/`, `providers/cloudflare/*/`) for component-specific documentation.
