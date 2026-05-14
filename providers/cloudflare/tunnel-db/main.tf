terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_id" "tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel" {
  account_id    = var.cloudflare_account_id
  name          = "${var.resource_prefix}-db-primary"
  tunnel_secret = random_id.tunnel_secret.b64_std
  config_src    = "cloudflare"
}

locals {
  tunnel_hostname = var.domain_name != "" ? "db-tunnel.${var.domain_name}" : ""
  enable_access   = var.domain_name != "" && var.zone_id != ""
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "tunnel_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id

  config = {
    ingress = concat(
      local.enable_access ? [
        {
          hostname = local.tunnel_hostname
          service  = "tcp://localhost:${var.db_port}"
          origin_request = {
            tcp_keep_alive  = 30
            connect_timeout = 10
          }
        }
      ] : [],
      [
        {
          service = "http_status:404"
        }
      ]
    )
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "tunnel" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

resource "cloudflare_dns_record" "tunnel" {
  count   = local.enable_access ? 1 : 0
  zone_id = var.zone_id
  name    = "db-tunnel"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
  comment = "DB tunnel for ${var.resource_prefix}"
}

resource "cloudflare_zero_trust_access_application" "db_tunnel" {
  count      = local.enable_access ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "${var.resource_prefix}-db-tunnel"
  type       = "self_hosted"
  domain     = local.tunnel_hostname

  destinations = [{
    type = "public"
    uri  = local.tunnel_hostname
  }]

  session_duration = var.session_duration

  policies = local.enable_access ? [
    {
      id         = cloudflare_zero_trust_access_policy.db_tunnel_allow[0].id
      precedence = 1
    }
  ] : []
}

resource "cloudflare_zero_trust_access_service_token" "db_tunnel" {
  count      = local.enable_access ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "${var.resource_prefix}-db-tunnel-client"
  duration   = var.service_token_duration
}

resource "cloudflare_zero_trust_access_policy" "db_tunnel_allow" {
  count      = local.enable_access ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "Allow Hetzner Servers"
  decision   = "allow"

  include = concat(
    length(var.allowed_cidrs) > 0 ? [
      for cidr in var.allowed_cidrs : {
        ip = {
          ip = cidr
        }
      }
    ] : [],
    [
      {
        service_token = {
          token_id = cloudflare_zero_trust_access_service_token.db_tunnel[0].id
        }
      }
    ]
  )
}
