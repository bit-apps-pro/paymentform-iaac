# Root-level variables for required module inputs
variable "neon_api_key" {
  description = "Neon API key for serverless database provisioning"
  type        = string
  sensitive   = true
}

variable "turso_api_token" {
  description = "Turso API token for tenant database provisioning"
  type        = string
  sensitive   = true
}

variable "desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  type        = number
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, sandbox, prod)"
  type        = string
}

# Domain and subdomain configuration
variable "domain_name" {
  description = "Root domain name for the application"
  type        = string
}

variable "api_subdomain" {
  description = "API subdomain for backend services (e.g., api.sandbox.paymentform.io)"
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "App subdomain for client dashboard (e.g., app.sandbox.paymentform.io)"
  type        = string
  default     = ""
}

variable "renderer_subdomain" {
  description = "Renderer subdomain for multi-tenant forms (e.g., *.sandbox.paymentform.io)"
  type        = string
  default     = ""
}
