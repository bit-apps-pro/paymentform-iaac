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

# ---------------------------------------------------------------------------
# R2 bucket that backs cdn-assets.paymentform.io.
#
# We diverge from the `cdn-worker` pattern used for tenant-uploaded assets
# (`cdn-ap.paymentform.io`) and bind the bucket to its custom domain natively.
# Rationale:
#   - Cache-Control + immutability is set on upload (no per-request rewriting).
#   - Content-hashed Next.js paths under `_next/static/{chunks,media}/<hash>`
#     make range / conditional-revalidation handling unnecessary — Cloudflare's
#     edge speaks HEAD/304 to R2 origin directly.
#   - One fewer Worker = one less moving part to operate.
# Documented in README.md alongside the Wrangler fallback procedure if a
# future provider change forces a Worker-fronted layout.
# ---------------------------------------------------------------------------
resource "cloudflare_r2_bucket" "renderer_static" {
  account_id = var.cloudflare_account_id
  name       = "${var.environment}-${var.bucket_name}"
  location   = var.location

  # The bucket is the source of truth for every shipped build's static assets.
  # Accidental destroy would 404 every running browser tab that hasn't picked
  # up the new HTML yet — keep it sticky.
  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Lifecycle — auto-delete `_next/static/...` objects whose R2 `LastModified`
# is older than `static_retention_days` (default 30).
#
# Pairs with CI's `rclone copy --no-check-dest` strategy: every CI run re-PUTs
# every chunk currently in the build's output, refreshing `LastModified`.
# Eviction therefore targets only chunks that have NOT appeared in any build
# for `static_retention_days` — exactly the "stale buildId never coming back"
# case we want to garbage-collect.
#
# Prefix `_next/static/` matches every layout we use: new sibling layout
# (`_next/static/chunks/...`, `media/...`, `<buildId>/...`) and the old
# wrapped layout if any pre-fix object lingers from an aborted upload.
#
# public/ is not uploaded to R2 (assetPrefix does not rewrite those URLs);
# no lifecycle entry needed.
# ---------------------------------------------------------------------------
resource "cloudflare_r2_bucket_lifecycle" "renderer_static" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.renderer_static.name

  rules = [
    {
      id      = "expire-old-next-static"
      enabled = true
      conditions = {
        prefix = "_next/static/"
      }
      delete_objects_transition = {
        condition = {
          type    = "Age"
          max_age = var.static_retention_days * 86400
        }
      }
    }
  ]
}

# ---------------------------------------------------------------------------
# CORS — tenant canonical hosts (e.g. pay.merchant.com) load HTML from their
# own origin and JS/CSS/font assets from cdn-assets.paymentform.io. Browsers
# treat that as cross-origin, so we explicitly allow GET/HEAD from any origin
# and expose the conditional-revalidation headers.
#
# `*` is the simplest correct value because:
#   - tenant canonical hostnames are unknown at apply time;
#   - the assets are public — no credentials cross the boundary
#     (next/script tags do not set crossorigin="use-credentials").
# Revisit if a future change ever introduces credentialed loads.
# ---------------------------------------------------------------------------
resource "cloudflare_r2_bucket_cors" "renderer_static" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.renderer_static.name

  rules = [
    {
      id = "renderer-static-public-read"
      allowed = {
        methods = ["GET", "HEAD"]
        origins = var.cors_origins
        headers = ["Range", "If-None-Match", "If-Modified-Since"]
      }
      expose_headers  = ["ETag", "Content-Length", "Content-Range", "Accept-Ranges"]
      max_age_seconds = 86400
    }
  ]
}

# ---------------------------------------------------------------------------
# Native R2 public-bucket custom domain. Cloudflare manages the DNS and TLS
# automatically once the domain is attached to the bucket — no Worker, no
# separate CNAME record.
# ---------------------------------------------------------------------------
resource "cloudflare_r2_custom_domain" "renderer_static" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.renderer_static.name
  domain      = var.custom_domain
  zone_id     = var.cloudflare_zone_id
  enabled     = true
  min_tls     = "1.2"
}
