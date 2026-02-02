# Cloudflare Module Variables

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for paymentform.io"
  type        = string
}

variable "environment" {
  description = "Environment name (sandbox, prod)"
  type        = string
}

variable "api_subdomain" {
  description = "API subdomain (e.g., api.sandbox.paymentform.io or api.paymentform.io)"
  type        = string
}

variable "app_subdomain" {
  description = "App subdomain (e.g., app.sandbox.paymentform.io or app.paymentform.io)"
  type        = string
}

variable "renderer_subdomain" {
  description = "Renderer wildcard subdomain (e.g., *.sandbox.paymentform.io)"
  type        = string
}

variable "renderer_origin_ip" {
  description = "Origin IP for renderer wildcard DNS record"
  type        = string
  default     = ""
}

variable "enable_load_balancer" {
  description = "Enable Cloudflare Load Balancer"
  type        = bool
  default     = true
}

variable "api_origin_ips" {
  description = "List of origin IPs for API backend"
  type        = list(string)
  default     = []
}

variable "app_origin_ips" {
  description = "List of origin IPs for App frontend"
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "Health check path for API"
  type        = string
  default     = "/health"
}

variable "notification_email" {
  description = "Email for load balancer notifications"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Enable Web Application Firewall"
  type        = bool
  default     = true
}

variable "enable_rate_limiting" {
  description = "Enable rate limiting"
  type        = bool
  default     = true
}

variable "rate_limit_requests" {
  description = "Number of requests allowed per minute"
  type        = number
  default     = 100
}

variable "standard_tags" {
  description = "Standard tags to apply to resources"
  type        = map(string)
  default     = {}
}
