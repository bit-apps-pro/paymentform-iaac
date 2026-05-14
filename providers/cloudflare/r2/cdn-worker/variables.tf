variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Workers permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for Worker route binding"
  type        = string
  default     = ""
  sensitive   = false
}

variable "worker_enabled" {
  description = "Enable Cloudflare Workers for public file serving"
  type        = bool
  default     = false
}

variable "regional_buckets" {
  description = "Map of region to bucket names for binding to workers"
  type        = map(object({
    bucket_name  = string
    jurisdiction = optional(string, "default")
  }))
  default = {}
}

variable "domain_prefix" {
  description = "Prefix for CDN subdomains (e.g., 'cdn' creates cdn-us, cdn-eu, cdn-ap)"
  type        = string
  default     = "cdn"
}

variable "base_domain" {
  description = "Base domain for CDN (e.g., paymentform.io)"
  type        = string
  default     = ""
}

variable "regional_domains" {
  description = "Map of region to full CDN domain (overrides domain_prefix/base_domain per region)"
  type        = map(string)
  default     = {}
}


