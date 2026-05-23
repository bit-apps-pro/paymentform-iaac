variable "environment" {
  description = "Environment name (dev, sandbox, prod). Prefixed onto the bucket name."
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with R2 admin + DNS edit permissions on the target zone."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone ID that owns `var.custom_domain`. R2 native custom-domain attachment writes its DNS into this zone."
  type        = string
}

variable "bucket_name" {
  description = "Bucket name without the environment prefix (e.g. `paymentform-renderer-static` becomes `prod-paymentform-renderer-static`)."
  type        = string
}

variable "custom_domain" {
  description = "Public hostname bound to the bucket (e.g. static.paymentform.io)."
  type        = string
}

variable "cors_origins" {
  description = "Allowed Origin values for CORS GET/HEAD. Defaults to `[*]` because tenant canonical hosts are unknown at apply time and assets are public."
  type        = list(string)
  default     = ["*"]
}

variable "static_retention_days" {
  description = "Days to retain `_next/static/<buildId>/...` objects before lifecycle deletes them. Sets the practical rollback window for hotfixes against older SHAs."
  type        = number
  default     = 30

  validation {
    condition     = var.static_retention_days >= 1 && var.static_retention_days <= 365
    error_message = "static_retention_days must be between 1 and 365."
  }
}

variable "location" {
  description = "R2 storage location hint. Matches the application-storage US bucket region for write-locality with our CI runners."
  type        = string
  default     = "wnam"
}
