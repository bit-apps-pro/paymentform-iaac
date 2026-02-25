# Root-level variables for required module inputs

# Core Configuration
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "paymentform"
}

variable "neon_database_url" {
  description = "Pre-created Neon PostgreSQL connection string (DATABASE_URL)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "turso_api_token" {
  description = "Turso API token (used by backend for DB management)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group (legacy fallback)"
  type        = number
  default     = 1
}

variable "backend_instance_type" {
  description = "EC2 instance type for the backend (Laravel/FrankenPHP) instance"
  type        = string
  default     = "t4g.micro"
}

variable "renderer_instance_type" {
  description = "EC2 instance type for the renderer (Next.js + Caddy) instance"
  type        = string
  default     = "t4g.micro"
}

variable "backend_desired_capacity" {
  description = "Desired EC2 instance count for backend ASG"
  type        = number
  default     = 1
}

variable "renderer_desired_capacity" {
  description = "Desired EC2 instance count for renderer ASG"
  type        = number
  default     = 1
}

variable "backend_ami_id" {
  description = "AMI ID for backend EC2 (Ubuntu 24.04 ARM64). Falls back to ami_id if empty."
  type        = string
  default     = ""
}

variable "renderer_ami_id" {
  description = "AMI ID for renderer EC2 (Ubuntu 24.04 ARM64). Falls back to ami_id if empty."
  type        = string
  default     = ""
}

variable "ghcr_token" {
  description = "GitHub Container Registry PAT (read:packages scope) for EC2 image pull"
  type        = string
  sensitive   = true
  default     = ""
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

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnets"
  type        = bool
  default     = true
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

variable "key_pair_name" {
  description = "Name of the SSH key pair for EC2 instances (optional)"
  type        = string
  default     = ""
}

# Application secrets — passed through to SSM module
variable "turso_auth_token" {
  description = "Turso auth token used for CLI operations"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pgadmin_default_password" {
  description = "PGAdmin default password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tenant_db_auth_token" {
  description = "Tenant database auth token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tenant_db_encryption_key" {
  description = "Tenant database encryption key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mail_password" {
  description = "SMTP mail password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_access_key_id" {
  description = "AWS access key ID for application use"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for application use"
  type        = string
  sensitive   = true
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_secret" {
  description = "Stripe secret key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_client_id" {
  description = "Stripe client ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_connect_webhook_secret" {
  description = "Stripe Connect webhook secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kv_store_api_token" {
  description = "Cloudflare KV store API token"
  type        = string
  sensitive   = true
  default     = ""
}
