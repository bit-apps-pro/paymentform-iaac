terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
  email     = var.cloudflare_api_email
}


# R2 Bucket for application storage (private files)
resource "cloudflare_r2_bucket" "application_storage" {
  account_id = var.cloudflare_account_id
  name       = "${var.environment}-${var.r2_bucket_name}"

  lifecycle {
    prevent_destroy = true
  }
}

# Cloudflare Worker for serving public files from R2
resource "cloudflare_workers_script" "cdn_worker" {
  count              = var.worker_enabled && var.worker_route_pattern != "" ? 1 : 0
  account_id         = var.cloudflare_account_id
  script_name        = "${var.environment}-cdn-worker"
  content            = file("${path.module}/worker/index.js")
  compatibility_date = "2024-01-01"

  # Bindings: R2 bucket and environment variables
  bindings = [
    {
      name        = "R2_BUCKET"
      type        = "r2_bucket"
      bucket_name = cloudflare_r2_bucket.application_storage.name
    },
    {
      name = "ENVIRONMENT"
      type = "plain_text"
      text = var.environment
    },
    {
      name = "CORS_ORIGINS"
      type = "plain_text"
      text = join(",", var.cors_allowed_origins)
    }
  ]
}

# Worker Route - binds Worker to domain pattern
# Requires zone_id to be passed from parent module
resource "cloudflare_workers_route" "cdn_route" {
  count   = var.worker_enabled && var.worker_route_pattern != "" && var.cloudflare_zone_id != "" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  pattern = var.worker_route_pattern
  script  = cloudflare_workers_script.cdn_worker[0].script_name
}

# CORS configuration for R2 bucket (via Worker)
# Note: R2 CORS is configured in the Worker response headers
