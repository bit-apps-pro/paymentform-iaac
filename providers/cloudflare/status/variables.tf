variable "environment" {
  description = "Environment name (e.g. prod-us)"
  type        = string
}

variable "resource_prefix" {
  description = "Resource name prefix (e.g. paymentform-p-us)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Workers + DNS edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Root domain (e.g. paymentform.io)"
  type        = string
}

variable "status_subdomain" {
  description = "Subdomain for the status page (e.g. status.paymentform.io)"
  type        = string
  default     = "status"
}

variable "status_admin_token" {
  description = "Admin token for incident API authentication"
  type        = string
  sensitive   = true
}

variable "log_ingest_token" {
  description = "Write-only token for backend services to ship logs into the worker's D1 logs table"
  type        = string
  sensitive   = true
}

variable "admin_allowed_countries" {
  description = "CSV of ISO-3166 country codes allowed to access /admin/*. Empty = unrestricted (token-gated only). CF-IPCountry is the source."
  type        = string
  default     = "BD"
}

variable "admin_allowed_ips" {
  description = "CSV of IPv4 addresses and CIDR ranges allowed to access /admin/*. Empty = unrestricted (rely on country+token). CF-Connecting-IP is the source."
  type        = string
  default     = ""
}

variable "services" {
  description = "List of services to monitor. Each entry: { name = string, health_url = string }"
  type = list(object({
    name       = string
    health_url = string
  }))
}

variable "standard_tags" {
  description = "Standard tags (unused for Cloudflare resources, kept for consistency)"
  type        = map(string)
  default     = {}
}
