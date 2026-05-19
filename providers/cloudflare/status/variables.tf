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
