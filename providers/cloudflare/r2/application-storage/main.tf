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

resource "cloudflare_r2_bucket" "application_storage" {
  for_each = var.regional_config

  account_id   = var.cloudflare_account_id
  name         = "${var.bucket_name_prefix}-${each.key}"
  location     = each.value.location
  jurisdiction = each.value.jurisdiction

  lifecycle {
    # prevent_destroy = true
  }
}
