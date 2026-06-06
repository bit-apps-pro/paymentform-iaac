terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Magic token gating the worker's `?__raw=1` self-fetch loop. Without this,
# any caller with a public CDN URL could append `?__raw=1` and drain R2 Class
# B reads. cf.image sub-request injects it as `X-CDN-Self-Token` header.
resource "random_id" "self_fetch_token" {
  byte_length = 24
}

locals {
  worker_configs = var.worker_enabled && length(var.regional_buckets) > 0 ? {
    for region, bucket in var.regional_buckets : region => {
      name         = "${var.environment}-cdn-worker-${region}"
      pattern      = length(var.regional_domains) > 0 && contains(keys(var.regional_domains), region) ? "${var.regional_domains[region]}/*" : "${var.domain_prefix}-${region}.${var.base_domain}/*"
      hostname     = length(var.regional_domains) > 0 && contains(keys(var.regional_domains), region) ? var.regional_domains[region] : "${var.domain_prefix}-${region}.${var.base_domain}"
      bucket       = bucket.bucket_name
      jurisdiction = bucket.jurisdiction
    }
  } : {}

  # Stable per-region ratelimit namespace ID. Workers ratelimit `namespace_id`
  # is per-script (Cloudflare scopes the counter to (script, namespace_id)), so
  # different regional scripts sharing the same numeric ID would NOT actually
  # cross-contaminate counters. We still allocate per-region IDs defensively
  # for forward-compat if CF flips the scope semantic, and so reading the TF
  # config makes the operator intent obvious.
  sorted_regions = sort(keys(local.worker_configs))
  ratelimit_namespace_ids = {
    for region in local.sorted_regions :
    region => tostring(1001 + index(local.sorted_regions, region))
  }
}

resource "cloudflare_workers_script" "cdn_worker" {
  for_each = local.worker_configs

  account_id         = var.cloudflare_account_id
  script_name        = each.value.name
  content            = file("${path.module}/../worker/index.js")
  compatibility_date = "2025-05-01"
  main_module        = "index.js"

  bindings = concat(
    [
      {
        name        = "R2_BUCKET"
        type        = "r2_bucket"
        bucket_name = each.value.bucket
        # Pass jurisdiction through verbatim; only "default" maps to null. Any
        # other value (eu, fedramp, ...) is forwarded so the binding lands on
        # the right jurisdiction bucket.
        jurisdiction = each.value.jurisdiction == "default" ? null : each.value.jurisdiction
      },
      {
        name = "ENVIRONMENT"
        type = "plain_text"
        text = var.environment
      },
      # Used by cf.image self-fetch loop to target the worker's own hostname.
      # Without this the inner fetch would 404 against `request.url`'s host
      # when the worker is bound to a custom domain.
      {
        name = "SELF_HOST"
        type = "plain_text"
        text = each.value.hostname
      },
      # Magic token verified on `?__raw=1` requests. Only the worker's own
      # cf.image self-fetch knows it (injected as X-CDN-Self-Token); external
      # `__raw=1` callers get 403 and can't drain R2 reads.
      {
        name = "SELF_FETCH_TOKEN"
        type = "secret_text"
        text = random_id.self_fetch_token.hex
      },
      {
        name         = "ABUSE_LIMITER"
        type         = "ratelimit"
        namespace_id = local.ratelimit_namespace_ids[each.key]
        simple = {
          limit  = var.transform_rate_limit_per_minute
          period = 60
        }
      }
    ],
    var.tenant_kv_namespace_id != "" ? [
      {
        name         = "TENANT_KV"
        type         = "kv_namespace"
        namespace_id = var.tenant_kv_namespace_id
      }
    ] : []
  )
}

resource "cloudflare_workers_custom_domain" "cdn_domain" {
  for_each = var.worker_enabled && nonsensitive(var.cloudflare_zone_id) != "" ? local.worker_configs : {}

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  hostname   = replace(each.value.pattern, "/*", "")
  service    = cloudflare_workers_script.cdn_worker[each.key].script_name
}
