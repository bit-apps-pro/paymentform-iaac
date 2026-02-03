# Cloudflare DNS and Load Balancing Module
# Manages DNS records, load balancing, WAF, and DDoS protection

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}


# DNS Record for API subdomain (proxied through Cloudflare)
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_subdomain
  content = "placeholder" # Will be updated by load balancer
  type    = "A"
  proxied = true
  ttl     = 1 # Automatic when proxied
  comment = "API endpoint - managed by Terraform"
}

# DNS Record for App/Client subdomain (proxied through Cloudflare)
resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.app_subdomain
  content = "placeholder" # Will be updated by load balancer
  type    = "A"
  proxied = true
  ttl     = 1 # Automatic when proxied
  comment = "Client dashboard - managed by Terraform"
}

# DNS Record for Renderer wildcard subdomain (DNS-only, not proxied)
resource "cloudflare_record" "renderer_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = var.renderer_subdomain
  content = var.renderer_origin_ip
  type    = "A"
  proxied = false # DNS-only for wildcard
  ttl     = 300
  comment = "Multi-tenant renderer wildcard - DNS only"
}

# Load Balancer Monitor for API health checks
resource "cloudflare_load_balancer_monitor" "api_monitor" {
  count = var.enable_load_balancer ? 1 : 0

  account_id       = var.cloudflare_account_id
  type             = "https"
  description      = "API health check"
  method           = "GET"
  path             = var.health_check_path
  port             = 443
  timeout          = 5
  interval         = 60
  retries          = 2
  expected_codes   = "200"
  follow_redirects = false
  allow_insecure   = false
  probe_zone       = var.cloudflare_zone_id
}

# Load Balancer Monitor for App health checks
resource "cloudflare_load_balancer_monitor" "app_monitor" {
  count = var.enable_load_balancer ? 1 : 0

  account_id       = var.cloudflare_account_id
  type             = "https"
  description      = "App health check"
  method           = "GET"
  path             = "/"
  port             = 443
  timeout          = 5
  interval         = 60
  retries          = 2
  expected_codes   = "200,301,302"
  follow_redirects = true
  allow_insecure   = false
  probe_zone       = var.cloudflare_zone_id
}

# Origin Pool for API (backend instances)
resource "cloudflare_load_balancer_pool" "api_pool" {
  count = var.enable_load_balancer ? 1 : 0

  account_id  = var.cloudflare_account_id
  name        = "${var.environment}-api-pool"
  description = "API backend pool for ${var.environment}"
  enabled     = true
  monitor     = cloudflare_load_balancer_monitor.api_monitor[0].id

  dynamic "origins" {
    for_each = var.api_origin_ips
    content {
      name    = "api-${origins.key}"
      address = origins.value
      enabled = true
      weight  = 1
    }
  }

  notification_email = var.notification_email
}

# Origin Pool for App (client instances)
resource "cloudflare_load_balancer_pool" "app_pool" {
  count = var.enable_load_balancer ? 1 : 0

  account_id  = var.cloudflare_account_id
  name        = "${var.environment}-app-pool"
  description = "App frontend pool for ${var.environment}"
  enabled     = true
  monitor     = cloudflare_load_balancer_monitor.app_monitor[0].id

  dynamic "origins" {
    for_each = var.app_origin_ips
    content {
      name    = "app-${origins.key}"
      address = origins.value
      enabled = true
      weight  = 1
    }
  }

  notification_email = var.notification_email
}

# Load Balancer for API
resource "cloudflare_load_balancer" "api_lb" {
  count = var.enable_load_balancer ? 1 : 0

  zone_id              = var.cloudflare_zone_id
  name                 = var.api_subdomain
  default_pool_ids     = [cloudflare_load_balancer_pool.api_pool[0].id]
  fallback_pool_id     = cloudflare_load_balancer_pool.api_pool[0].id
  description          = "Load balancer for API - ${var.environment}"
  proxied              = true
  steering_policy      = "dynamic_latency"
  session_affinity     = "cookie"
  session_affinity_ttl = 3600

  session_affinity_attributes {
    drain_duration = 60
  }
}

# Load Balancer for App
resource "cloudflare_load_balancer" "app_lb" {
  count = var.enable_load_balancer ? 1 : 0

  zone_id              = var.cloudflare_zone_id
  name                 = var.app_subdomain
  default_pool_ids     = [cloudflare_load_balancer_pool.app_pool[0].id]
  fallback_pool_id     = cloudflare_load_balancer_pool.app_pool[0].id
  description          = "Load balancer for App - ${var.environment}"
  proxied              = true
  steering_policy      = "dynamic_latency"
  session_affinity     = "cookie"
  session_affinity_ttl = 3600

  session_affinity_attributes {
    drain_duration = 60
  }
}

# Zone Settings for SSL/TLS
resource "cloudflare_zone_settings_override" "paymentform_settings" {
  zone_id = var.cloudflare_zone_id

  settings {
    # SSL/TLS Settings
    ssl                      = "strict"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"

    # Security Settings
    security_level = "medium"
    browser_check  = "on"
    challenge_ttl  = 1800

    # Performance Settings
    brotli      = "on"
    early_hints = "on"
    http2       = "on"
    http3       = "on"
    zero_rtt    = "on"

    # Caching Settings (only for proxied records)
    cache_level = "aggressive"
  }
}

# WAF Managed Ruleset (OWASP Core)
resource "cloudflare_ruleset" "waf_managed" {
  count = var.enable_waf ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${var.environment}-waf-managed"
  description = "Managed WAF ruleset for ${var.environment}"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee" # OWASP Core Ruleset
    }
    expression  = "(http.host eq \"${var.api_subdomain}\" or http.host eq \"${var.app_subdomain}\")"
    description = "Execute OWASP Core Ruleset"
    enabled     = true
  }
}

# Rate Limiting Rule
resource "cloudflare_ruleset" "rate_limiting" {
  count = var.enable_rate_limiting ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  name        = "${var.environment}-rate-limiting"
  description = "Rate limiting for API endpoints"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules {
    action = "block"
    action_parameters {
      response {
        status_code  = 429
        content      = "Too many requests"
        content_type = "text/plain"
      }
    }
    ratelimit {
      characteristics     = ["ip.src"]
      period              = 60
      requests_per_period = var.rate_limit_requests
      mitigation_timeout  = 600
    }
    expression  = "(http.host eq \"${var.api_subdomain}\")"
    description = "Rate limit API requests"
    enabled     = true
  }
}

# Page Rule for caching static assets
resource "cloudflare_page_rule" "cache_static_assets" {
  zone_id  = var.cloudflare_zone_id
  target   = "${var.app_subdomain}/*"
  priority = 1

  actions {
    cache_level       = "cache_everything"
    edge_cache_ttl    = 7200
    browser_cache_ttl = 3600
  }
}
