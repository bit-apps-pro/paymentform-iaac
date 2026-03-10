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

resource "cloudflare_r2_bucket" "ssl_config" {
  count = var.enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "${var.environment}-${var.r2_bucket_name}"

  lifecycle {
    # prevent_destroy = true
  }
}
