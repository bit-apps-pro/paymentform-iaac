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

# Cloudflare configuration
variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS and Load Balancer management"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for paymentform.io"
  type        = string
  sensitive   = true
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

variable "enable_ecr" {
  description = "Enable provisioning of ECR repositories (for sandbox and prod)"
  type        = bool
  default     = false
}

variable "ecr_repositories" {
  description = "List of ECR repository/service names to create for non-dev environments"
  type        = list(string)
  default     = ["backend", "client", "renderer", "admin"]
}
