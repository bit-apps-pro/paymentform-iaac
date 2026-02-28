# Cloudflare Container Module
# Reusable module for deploying a single container instance

terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  full_container_name = "${var.resource_prefix}-${var.container_name}"
}

# Container Registry Credential
resource "cloudflare_registry_credential" "this" {
  count = var.container_enabled ? 1 : 0

  account_id  = var.cloudflare_account_id
  name        = "${local.full_container_name}-credential"
  registry    = var.registry_url
  username    = var.registry_username
  password    = var.registry_password
}

# Cloudflare Container Deployment
resource "cloudflare_container" "this" {
  count = var.container_enabled ? 1 : 0

  account_id             = var.cloudflare_account_id
  name                   = local.full_container_name
  registry_credential_id = cloudflare_registry_credential.this[0].id

  image = var.container_image

  deployment {
    cpu       = var.deployment_cpu
    memory_mb = var.deployment_memory_mb
    instances = var.instance_min_count

    dynamic "env" {
      for_each = var.container_env_vars
      content {
        name  = env.key
        value = env.value
      }
    }
  }

  tags = merge(
    var.standard_tags,
    {
      Name        = local.full_container_name
      Application = var.container_name
    }
  )
}

# DNS Record for Container
resource "cloudflare_dns_record" "this" {
  count = var.container_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = "${local.full_container_name}.containers.cloudflare.com"
  proxied = var.domain_proxied
  ttl     = var.domain_proxied ? 1 : 120
  comment = "${var.container_name} container for ${var.environment}"
}
