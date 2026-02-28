# Cloudflare R2 Module
# Manages R2 buckets for application storage and SSL certificate persistence

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
  app_storage_bucket_name    = "${var.environment}-${var.r2_bucket_name}"
  public_bucket_name         = var.r2_public_bucket_name != "" ? "${var.environment}-${var.r2_public_bucket_name}" : null
  ssl_config_bucket_name     = "${var.environment}-${var.r2_ssl_bucket_name}"
}

# Application Storage Bucket (private files)
resource "cloudflare_r2_bucket" "application_storage" {
  account_id = var.cloudflare_account_id
  name       = local.app_storage_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Public Files Bucket (optional)
resource "cloudflare_r2_bucket" "public_files" {
  count = var.r2_public_bucket_name != "" ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = local.public_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# SSL Config Bucket for Caddy certificates
# Used by renderer container to persist TLS certificates across restarts
resource "cloudflare_r2_bucket" "ssl_config" {
  count = var.r2_ssl_bucket_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = local.ssl_config_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Lifecycle Rule for SSL Config Bucket
# Automatically expires old certificate files
resource "cloudflare_r2_bucket_lifecycle_rule" "ssl_config" {
  count = var.r2_ssl_bucket_enabled && var.lifecycle_rules_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  bucket     = cloudflare_r2_bucket.ssl_config[0].name

  rule_id = "expire-old-certs"
  enabled = true

  expiration {
    days = var.ssl_cert_retention_days
  }

  prefix = "expired/"
}

# Cloudflare Worker for serving public files from R2
resource "cloudflare_workers_script" "cdn_worker" {
  count = var.worker_enabled && var.worker_route_pattern != "" ? 1 : 0

  account_id         = var.cloudflare_account_id
  script_name        = "${var.environment}-cdn-worker"
  content            = file("${path.module}/worker/index.js")
  compatibility_date = "2024-01-01"

  bindings {
    name        = "R2_BUCKET"
    type        = "r2_bucket"
    bucket_name = cloudflare_r2_bucket.application_storage.name
  }

  bindings {
    name = "ENVIRONMENT"
    type = "plain_text"
    text = var.environment
  }

  bindings {
    name = "CORS_ORIGINS"
    type = "plain_text"
    text = join(",", var.cors_allowed_origins)
  }
}

# Worker Route - binds Worker to domain pattern
resource "cloudflare_workers_route" "cdn_route" {
  count = var.worker_enabled && var.worker_route_pattern != "" && var.cloudflare_zone_id != "" ? 1 : 0

  zone_id = var.cloudflare_zone_id
  pattern = var.worker_route_pattern
  script  = cloudflare_workers_script.cdn_worker[0].script_name
}
