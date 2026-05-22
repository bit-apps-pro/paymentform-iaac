# Cloudflare KV Module
# Reusable module for a single KV namespace

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
  namespace_title = "${var.resource_prefix}-${var.namespace_name}"
}

# KV Namespace
resource "cloudflare_workers_kv_namespace" "this" {
  count = var.namespace_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  title      = local.namespace_title
}

resource "null_resource" "deploy_kv_store" {
  count = var.namespace_enabled && var.deploy_worker ? 1 : 0

  triggers = {
    namespace_id = try(cloudflare_workers_kv_namespace.this[0].id, "")
    worker_path  = var.worker_path
    environment  = var.environment
    api_token    = var.kv_store_api_token != "" ? "set" : "not_set"
  }

  provisioner "local-exec" {
    command = <<-EOT
      "${path.module}/scripts/deploy-worker.sh" "${try(cloudflare_workers_kv_namespace.this[0].id, "")}" "${var.worker_path}" "${var.environment}" "${var.cloudflare_account_id}" "${var.kv_store_api_token}"
    EOT
  }
}
