# Cloudflare KV Module
# Reusable module for a single KV namespace

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
  namespace_title = "${var.resource_prefix}-${var.namespace_name}"
}

# KV Namespace
resource "cloudflare_workers_kv_namespace" "this" {
  count = var.namespace_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  title      = local.namespace_title
}
