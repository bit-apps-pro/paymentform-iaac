# Cloudflare DNS Module
# Manages DNS records, load balancing, WAF, and rate limiting

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
  email     = var.cloudflare_api_email
}

locals {
  # Use container endpoints if available, otherwise fall back to IPs
  app_target      = var.app_container_endpoint != "" ? var.app_container_endpoint : (length(var.app_origin_ips) > 0 ? var.app_origin_ips[0] : "127.0.0.1")
  api_target      = length(var.api_origin_ips) > 0 ? var.api_origin_ips[0] : "127.0.0.1"
  renderer_target = var.renderer_container_endpoint != "" ? var.renderer_container_endpoint : var.renderer_origin_ip
}

# Geo-routing A records for API (multi-region)
resource "cloudflare_dns_record" "api_region" {
  for_each = var.enable_geo_routing ? var.region_endpoints : tomap({})

  zone_id = var.cloudflare_zone_id
  name    = var.api_subdomain
  content = each.value
  type    = "A"
  proxied = true
  ttl     = 1
  comment = "API endpoint - ${each.key} region"
}

# Default API record (when not using geo-routing)
resource "cloudflare_dns_record" "api" {
  count   = var.enable_geo_routing ? 0 : 1
  zone_id = var.cloudflare_zone_id
  name    = var.api_subdomain
  content = local.api_target
  type    = length(var.api_origin_ips) > 0 ? "A" : "CNAME"
  proxied = true
  ttl     = 1
  comment = "API endpoint - proxied through Cloudflare"
}

# DNS Record for App subdomain (proxied through Cloudflare)
# Points to container endpoint or EC2 instance
resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.app_subdomain
  content = local.app_target
  type    = var.app_container_endpoint != "" ? "CNAME" : "A"
  proxied = true
  ttl     = 1
  comment = "App dashboard - proxied through Cloudflare"
}

# DNS Record for Renderer wildcard subdomain
# DNS-only (not proxied) - Caddy on container handles on-demand TLS directly
resource "cloudflare_dns_record" "renderer_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = var.renderer_subdomain
  content = local.renderer_target
  type    = var.renderer_container_endpoint != "" ? "CNAME" : "A"
  proxied = false
  ttl     = 120
  comment = "Multi-tenant renderer wildcard - DNS-only (Caddy handles TLS directly)"
}

# WAF Custom Ruleset - Block common attacks
resource "cloudflare_ruleset" "waf_custom" {
  count = var.enable_waf ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${var.environment}-waf-custom"
  description = "Custom WAF rules for ${var.environment}"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [{
    description = "Block high threat score requests"
    expression  = "(cf.threat_score > 50)"
    action      = "block"
  }]
}

# Rate Limiting Rule
resource "cloudflare_ruleset" "rate_limiting" {
  count = var.cloudflare_plan == "business" || var.cloudflare_plan == "enterprise" ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${var.environment}-rate-limiting"
  description = "Rate limiting for API endpoints"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [{
    description = "Rate limit API requests"
    expression  = "(http.host eq \"${var.api_subdomain}\" and http.request.method eq \"POST\")"
    action      = "block"
    ratelimit = {
      characteristics     = ["ip.src"]
      period              = 60
      requests_per_period = var.rate_limit_requests
      mitigation_timeout  = 600
    }
  }]
}

# Cache Rules for static assets
resource "cloudflare_ruleset" "cache_rules" {
  count = var.cloudflare_plan == "business" || var.cloudflare_plan == "enterprise" ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${var.environment}-cache-rules"
  description = "Cache rules for static assets"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      description = "Cache static assets"
      expression  = "(http.host eq \"${var.app_subdomain}\" and (http.request.uri.path matches \"\\.(js|css|png|jpg|svg|gif|woff|woff2)$\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 7200
        }
        browser_ttl = {
          mode    = "override_origin"
          default = 3600
        }
      }
    },
    {
      description = "Bypass cache for HTML pages"
      expression  = "(http.host eq \"${var.app_subdomain}\" and (http.request.uri.path matches \"\\.(html|php)$\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
    }
  ]
}

# ============================================================================
# Cloudflare Load Balancer (for multi-region geo-steering)
# NOTE: For Pro plan with Load Balancer add-on ($5/mo), configure manually in 
# Cloudflare dashboard or update when Terraform provider syntax is verified.
# 
# To enable via Terraform:
# 1. Create health monitors
# 2. Create pools for each region (us, eu, au)
# 3. Create load balancer with country/pop pools
# 
# Or configure manually: Cloudflare Dashboard > Load Balancing > Create Load Balancer
# ============================================================================

# Placeholder - load balancer can be added once Terraform provider syntax is confirmed
# For now, use Cloudflare dashboard to set up geo-steering
