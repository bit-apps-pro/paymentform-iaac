# Cloudflare Status Page Worker Module
#
# Deploys a lightweight Cloudflare Worker that polls all service health endpoints
# in parallel and serves an HTML status page + JSON /status endpoint.

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
  worker_name   = "${var.resource_prefix}-status"
  services_json = jsonencode(var.services)
}

# KV namespace for incidents and health data
resource "cloudflare_workers_kv_namespace" "incidents" {
  account_id = var.cloudflare_account_id
  title      = "${var.resource_prefix}-incidents"
}

# D1 database for log ingestion. Named with the PAYMENT_FORM_ prefix per request
# so it's grep-able across the Cloudflare dashboard alongside future
# paymentform-owned D1s. Bound to the worker as `LOGS_DB`.
resource "cloudflare_d1_database" "logs" {
  account_id = var.cloudflare_account_id
  name       = "PAYMENT_FORM_${var.environment}_logs"

  # API rejects PUT when read_replication is absent (code 7400). Provider only
  # exposes this attribute from 5.19+. Admin-only reads, so replicas disabled.
  read_replication = {
    mode = "disabled"
  }
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
    cloudflare_d1_database.logs.id,
    var.cloudflare_account_id,
    filesha256("${path.module}/worker.js"),
    filesha256("${path.module}/health.js"),
    filesha256("${path.module}/page.js"),
    filesha256("${path.module}/auth.js"),
    filesha256("${path.module}/feed.js"),
    filesha256("${path.module}/incidents.js"),
    filesha256("${path.module}/logs.js"),
    filesha256("${path.module}/access.js"),
    filesha256("${path.module}/admin.js"),
    filesha256("${path.module}/schema.sql"),
    sensitive(var.status_admin_token),
    sensitive(var.log_ingest_token),
    var.admin_allowed_countries,
    var.admin_allowed_ips,
  ]

  provisioner "local-exec" {
    # wrangler.toml is sed-patched in place each apply so terraform owns the
    # binding IDs. Order: name + account → KV id → D1 name + id → schema apply
    # → worker deploy → admin/ingest secret puts.
    command = <<-EOT
      cd ${path.module} && \
      sed -i 's/^name = ".*"/name = "${local.worker_name}"/' wrangler.toml && \
      sed -i 's/^account_id = ".*"/account_id = "${var.cloudflare_account_id}"/' wrangler.toml && \
      sed -i '/^\[\[kv_namespaces\]\]/,/^\[/ s/^id = ".*"/id = "${cloudflare_workers_kv_namespace.incidents.id}"/' wrangler.toml && \
      sed -i '/^\[\[d1_databases\]\]/,/^\[/ s/^database_name = ".*"/database_name = "${cloudflare_d1_database.logs.name}"/' wrangler.toml && \
      sed -i '/^\[\[d1_databases\]\]/,/^\[/ s/^database_id = ".*"/database_id = "${cloudflare_d1_database.logs.id}"/' wrangler.toml && \
      wrangler d1 execute "${cloudflare_d1_database.logs.name}" --remote --file schema.sql --yes && \
      wrangler deploy \
        --var "SERVICES_JSON:$SERVICES_JSON" \
        --var "ADMIN_ALLOWED_COUNTRIES:$ADMIN_ALLOWED_COUNTRIES" \
        --var "ADMIN_ALLOWED_IPS:$ADMIN_ALLOWED_IPS" && \
      echo "$STATUS_ADMIN_TOKEN" | wrangler secret put ADMIN_TOKEN && \
      echo "$LOG_INGEST_TOKEN"  | wrangler secret put LOG_INGEST_TOKEN
    EOT

    environment = {
      CF_API_TOKEN             = var.cloudflare_api_token
      SERVICES_JSON            = local.services_json
      STATUS_ADMIN_TOKEN       = var.status_admin_token
      LOG_INGEST_TOKEN         = var.log_ingest_token
      ADMIN_ALLOWED_COUNTRIES  = var.admin_allowed_countries
      ADMIN_ALLOWED_IPS        = var.admin_allowed_ips
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
