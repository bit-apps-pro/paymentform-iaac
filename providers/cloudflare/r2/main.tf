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

# Application Storage Bucket
module "application-storage" {
  source = "./application-storage"

  environment           = var.environment
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = var.r2_bucket_name
}

# SSL Config Bucket for Caddy certificates
module "ssl-config" {
  source = "./ssl-config"

  environment           = var.environment
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = var.r2_ssl_bucket_name
  enabled               = var.r2_ssl_bucket_enabled
}

# Public Files Bucket
module "public-files" {
  source = "./public-files"

  count                 = var.r2_public_bucket_name != "" ? 1 : 0
  environment           = var.environment
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = var.r2_public_bucket_name
}

# CDN Worker
module "cdn-worker" {
  source = "./cdn-worker"

  count                   = var.worker_enabled ? 1 : 0
  environment             = var.environment
  cloudflare_account_id   = var.cloudflare_account_id
  cloudflare_api_token    = var.cloudflare_api_token
  cloudflare_zone_id      = var.cloudflare_zone_id
  worker_enabled          = var.worker_enabled
  worker_route_pattern    = var.worker_route_pattern
  application_bucket_name = module.application-storage.bucket_name
}
