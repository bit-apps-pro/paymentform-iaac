# Root-level variables for required module inputs

# Core Configuration
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "paymentform"
}

variable "neon_api_key" {
  description = "Neon API key for serverless database provisioning"
  type        = string
  sensitive   = true
  default     = ""
}

variable "turso_api_token" {
  description = "Turso API token for tenant database provisioning"
  type        = string
  sensitive   = true
  default     = ""
}

variable "turso_organization" {
  description = "Turso organization name"
  type        = string
  default     = ""
}

variable "desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  type        = number
  default     = 1
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
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for paymentform.io"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
  default     = ""
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

# Image Registry Configuration
variable "image_registry_type" {
  description = "Type of image registry to use (local, ecr, ghcr)"
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "ecr", "ghcr"], var.image_registry_type)
    error_message = "image_registry_type must be one of: local, ecr, ghcr"
  }
}

# Monitoring & Backup Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "enable_encryption" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

# Resource Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center for resource billing"
  type        = string
  default     = "development"
}

variable "owner" {
  description = "Owner or team responsible for resources"
  type        = string
  default     = "devops-team"
}

variable "managed_by" {
  description = "Tool used to manage infrastructure"
  type        = string
  default     = "opentofu"
}
