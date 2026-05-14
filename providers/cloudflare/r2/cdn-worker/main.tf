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
  worker_configs = var.worker_enabled && length(var.regional_buckets) > 0 ? {
    for region, bucket in var.regional_buckets : region => {
      name       = "${var.environment}-cdn-worker-${region}"
      pattern    = length(var.regional_domains) > 0 && contains(keys(var.regional_domains), region) ? "${var.regional_domains[region]}/*" : "${var.domain_prefix}-${region}.${var.base_domain}/*"
      bucket     = bucket.bucket_name
      jurisdiction = bucket.jurisdiction
    }
  } : {}
}

resource "cloudflare_workers_script" "cdn_worker" {
  for_each = local.worker_configs

  account_id         = var.cloudflare_account_id
  script_name        = each.value.name
  content            = file("${path.module}/../worker/index.js")
  compatibility_date = "2025-05-01"
  main_module        = "index.js"

  bindings = [
    {
      name        = "R2_BUCKET"
      type        = "r2_bucket"
      bucket_name = each.value.bucket
      jurisdiction = each.value.jurisdiction == "eu" ? "eu" : null
    },
    {
      name = "ENVIRONMENT"
      type = "plain_text"
      text = var.environment
    }
  ]
}

resource "cloudflare_workers_custom_domain" "cdn_domain" {
  for_each = var.worker_enabled && nonsensitive(var.cloudflare_zone_id) != "" ? local.worker_configs : {}

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  hostname   = replace(each.value.pattern, "/*", "")
  service    = cloudflare_workers_script.cdn_worker[each.key].script_name
}
