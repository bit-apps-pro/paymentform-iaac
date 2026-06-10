# Client Dashboard

## Overview

The client dashboard is a React SPA (Vite + TanStack Router) deployed as a Cloudflare Container via `module.paymentform_client` (source: `providers/cloudflare/containers/`).

## Configuration

```hcl
module "paymentform_client" {
  source = "../../providers/cloudflare/containers"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "client"
  container_image   = var.client_container_image
  container_enabled = false    # set to true to deploy

  domain_name    = "app.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}
```

## Deployment

The container is deployed via `wrangler containers push` and `wrangler deploy`, triggered by Terraform's `local-exec` provisioner. The module:

1. Updates `wrangler.toml` with the container name, account ID, image, class name, and max instances.
2. Pushes the image to Cloudflare's container registry.
3. Deploys the container environment.

### Deploying or Updating

```bash
cd environments/prod

# Deploy only the client container
tofu apply -target=module.paymentform_client

# Update the client image
make update-client IMAGE_TAG=v1.2.3
```

### Enabling the Container

The `container_enabled` variable controls whether the container is deployed. Set to `true` to deploy:

```hcl
container_enabled = true
```

When `false`, no DNS record or container deployment is created.

## DNS

When `container_enabled = true`, a CNAME record is created:

- `app.paymentform.io` → `paymentform-prod-client.containers.cloudflare.com`
- Proxied through Cloudflare (orange cloud)

## Container Image

The image is pulled from GHCR. Set the image tag via `var.client_container_image`:

```hcl
# In terraform.tfvars
client_container_image = "ghcr.io/org/client:v1.2.3"
```

Authentication uses `var.ghcr_username` and `var.ghcr_token` (stored in `TF_VAR_ghcr_token`).

## Environment Variables

Key env vars injected into the client container:

| Variable | Value |
|----------|-------|
| `API_URL` | `https://api.paymentform.io` |
| `DOMAIN` | `https://app.paymentform.io` |
| `COOKIE_DOMAIN` | `.paymentform.io` |
| `FORM_RENDER_URL` | `https://renderer.paymentform.io/` |
| `STRIPE_KEY` | Stripe publishable key |
| `NODE_ENV` | `production` |

## Monitoring

Check container status via Cloudflare dashboard: Workers & Pages → Containers → `paymentform-prod-client`.

Health check endpoint: `https://app.paymentform.io/api/health`