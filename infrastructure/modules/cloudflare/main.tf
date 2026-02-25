# Cloudflare DNS and Load Balancing Module
# Manages DNS records, load balancing, WAF, and DDoS protection

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
}


# DNS Record for API subdomain (proxied through Cloudflare)
# Routes to first EC2 instance; Traefik on EC2 handles load balancing internally
resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_subdomain
  content = length(var.api_origin_ips) > 0 ? var.api_origin_ips[0] : "127.0.0.1"
  type    = "A"
  proxied = true
  ttl     = 1 # Automatic when proxied
  comment = "API endpoint - proxied through Cloudflare"
}

# DNS Record for App/Client subdomain (proxied through Cloudflare)
# Routes to first EC2 instance; Traefik on EC2 handles routing to frontend services
resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.app_subdomain
  content = length(var.app_origin_ips) > 0 ? var.app_origin_ips[0] : "127.0.0.1"
  type    = "A"
  proxied = true
  ttl     = 1 # Automatic when proxied
  comment = "App dashboard - proxied through Cloudflare"
}

# DNS Record for Renderer wildcard subdomain (DNS-only — no Cloudflare proxy)
# Caddy on the renderer EC2 handles on-demand TLS directly for wildcard subdomains;
# Cloudflare proxying would break the TLS handshake for wildcard certs.
resource "cloudflare_dns_record" "renderer_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = var.renderer_subdomain
  content = var.renderer_origin_ip
  type    = "A"
  proxied = false
  ttl     = 120 # TTL must be explicit for DNS-only records (ttl=1 is only valid when proxied)
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

  rules = [
    {
      description = "Block high threat score requests"
      expression  = "(cf.threat_score > 50)"
      action      = "block"
    }
  ]
}

# Rate Limiting Rule
resource "cloudflare_ruleset" "rate_limiting" {
  count = var.enable_rate_limiting ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${var.environment}-rate-limiting"
  description = "Rate limiting for API endpoints"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      description = "Rate limit API requests"
      expression  = "(http.host eq \"${var.api_subdomain}\" and http.request.method eq \"POST\")"
      action      = "block"
      ratelimit = {
        characteristics     = ["ip.src"]
        period              = 60
        requests_per_period = var.rate_limit_requests # Updated attribute name
        mitigation_timeout  = 600
      }
    }
  ]
}

# Cache Rules for static assets
resource "cloudflare_ruleset" "cache_rules" {
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
