# Cloudflare Status Page Worker Module
#
# Deploys a lightweight Cloudflare Worker that polls all service health endpoints
# in parallel and serves an HTML status page + JSON /status endpoint.

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
  worker_name   = "${var.resource_prefix}-status"
  services_json = jsonencode(var.services)
}

# KV namespace for incidents and health data
resource "cloudflare_workers_kv_namespace" "incidents" {
  account_id = var.cloudflare_account_id
  title      = "${var.resource_prefix}-incidents"
}

# DNS record: status.{domain} → proxied through Cloudflare to the worker
resource "cloudflare_dns_record" "status" {
  zone_id = var.cloudflare_zone_id
  name    = "${var.status_subdomain}.${var.domain_name}"
  type    = "AAAA"
  content = "100::"
  proxied = true
  ttl     = 1
  comment = "Status page worker for ${var.environment}"
}

# Worker script — deployed via wrangler so it bundles worker.js + health.js + page.js.
# cloudflare_workers_script only uploads a single file and cannot resolve local imports,
# so we use terraform_data + local-exec (same pattern as the kv module).
resource "terraform_data" "deploy_status_worker" {
  triggers_replace = [
    local.worker_name,
    local.services_json,
    cloudflare_workers_kv_namespace.incidents.id,
    var.cloudflare_account_id,
    filesha256("${path.module}/worker.js"),
    filesha256("${path.module}/health.js"),
    filesha256("${path.module}/page.js"),
    filesha256("${path.module}/auth.js"),
    filesha256("${path.module}/feed.js"),
    filesha256("${path.module}/incidents.js"),
    sensitive(var.status_admin_token),
  ]

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module} && \
      sed -i 's/^name = ".*"/name = "${local.worker_name}"/' wrangler.toml && \
      sed -i 's/^account_id = ".*"/account_id = "${var.cloudflare_account_id}"/' wrangler.toml && \
      sed -i 's/^id = ".*"/id = "${cloudflare_workers_kv_namespace.incidents.id}"/' wrangler.toml && \
      wrangler deploy --var "SERVICES_JSON:$SERVICES_JSON" && \
      echo "$STATUS_ADMIN_TOKEN" | wrangler secret put ADMIN_TOKEN
    EOT

    environment = {
      CF_API_TOKEN       = var.cloudflare_api_token
      SERVICES_JSON      = local.services_json
      STATUS_ADMIN_TOKEN = var.status_admin_token
    }
  }
}

# Route: status.{domain}/* — created separately so it can reference the worker name
# without depending on the script resource (which is now managed by wrangler).
resource "cloudflare_workers_route" "status" {
  depends_on = [terraform_data.deploy_status_worker]

  zone_id = var.cloudflare_zone_id
  pattern = "${var.status_subdomain}.${var.domain_name}/*"
  script  = local.worker_name
}
