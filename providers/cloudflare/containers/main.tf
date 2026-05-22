# Cloudflare Container Module
# Reusable module for deploying a single container instance

terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  full_container_name    = "${var.resource_prefix}-${var.container_name}"
  class_name             = "App${title(var.container_name)}"
  binding_name           = "APP_${upper(var.container_name)}"
  container_env_vars_str = join(", ", [for k, v in var.container_env_vars : "${k}=\"${v}\"" if v != null])
  image                  = element(split("/", var.container_image), length(split("/", var.container_image)) - 1)
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

# Deploy container using wrangler
resource "terraform_data" "deploy_container" {
  count = var.container_enabled ? 1 : 0

  triggers_replace = [
    var.container_image,
    local.full_container_name,
    var.cloudflare_account_id,
    var.prod_image,
    jsonencode(var.container_env_vars),
    var.instance_max_count
  ]

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module} && \
      sed -i 's/^name = ".*"/name = "${var.resource_prefix}-${var.container_name}"/' wrangler.toml && \
      sed -i 's/^account_id = ".*"/account_id = "${var.cloudflare_account_id}"/' wrangler.toml && \
      sed -i 's/^image = ".*"/image = "${var.container_image}"/' wrangler.toml && \
      sed -i 's/^class_name = ".*"/class_name = "${local.class_name}"/' wrangler.toml && \
      sed -i 's/^max_instances = .*/max_instances = ${var.instance_max_count}/' wrangler.toml && \
      wrangler containers push ${local.image} && \
      wrangler deploy --env ${var.environment}
    EOT

    environment = merge(var.container_env_vars, {
      CF_API_TOKEN = var.cloudflare_api_token
    })
  }
}
