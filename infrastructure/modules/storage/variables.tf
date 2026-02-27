variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cloudflare_api_email" {
  description = "Cloudflare account email (required for API token authentication)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID for R2 storage"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with R2 and Worker permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for Worker route binding"
  type        = string
  default     = ""
}

variable "r2_bucket_name" {
  description = "Name of the R2 bucket for application storage"
  type        = string
}

variable "r2_public_bucket_name" {
  description = "Name of the R2 bucket for public files (served via Worker)"
  type        = string
  default     = ""
}

variable "worker_enabled" {
  description = "Enable Cloudflare Worker for public file serving"
  type        = bool
  default     = true
}

variable "worker_route_pattern" {
  description = "Route pattern for the Worker (e.g., cdn.example.com/*)"
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "log_retention_days" {
  description = "Number of days to retain logs (for future logging integration)"
  type        = number
  default     = 30
}
