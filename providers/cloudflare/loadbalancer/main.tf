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
  api_token = var.api_token
}

# Load Balancer
resource "cloudflare_load_balancer" "main" {
  zone_id     = var.zone_id
  name        = var.lb_name
  description = var.description

  fallback_pool = var.fallback_pool_id
  default_pools = var.default_pool_ids

  steering_policy = var.steering_policy
  proxied        = var.proxied
  ttl            = var.ttl
}
