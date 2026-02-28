# Cloudflare R2 Module Variables

variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with R2 permissions"
  type        = string
  sensitive   = true
}

# Application Storage Bucket
variable "r2_bucket_name" {
  description = "Name of the R2 bucket for application storage (without environment prefix)"
  type        = string
}

variable "r2_public_bucket_name" {
  description = "Name of the R2 bucket for public files (optional)"
  type        = string
  default     = ""
}

# SSL Config Bucket for Caddy certificates
variable "r2_ssl_bucket_name" {
  description = "Name of the R2 bucket for storing Caddy SSL certificates"
  type        = string
  default     = "paymentform-ssl-config"
}

variable "r2_ssl_bucket_enabled" {
  description = "Enable R2 bucket for SSL certificate storage"
  type        = bool
  default     = true
}

# CORS Configuration
variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

# Lifecycle Rules
variable "lifecycle_rules_enabled" {
  description = "Enable lifecycle rules for buckets"
  type        = bool
  default     = true
}

variable "ssl_cert_retention_days" {
  description = "Number of days to retain old SSL certificates"
  type        = number
  default     = 30
}

# Worker Configuration (optional, for public file serving)
variable "worker_enabled" {
  description = "Enable Cloudflare Worker for public file serving"
  type        = bool
  default     = false
}

variable "worker_route_pattern" {
  description = "Route pattern for the Worker (e.g., cdn.example.com/*)"
  type        = string
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for Worker route binding"
  type        = string
  default     = ""
}
