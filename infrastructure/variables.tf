# Root-level variables for common infrastructure configuration
# These variables are shared across all environments and regions

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "paymentform"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment (dev, sandbox, prod)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "sandbox", "prod"], var.environment)
    error_message = "Environment must be one of: dev, sandbox, prod."
  }
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

variable "region" {
  description = "AWS region for deployment"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.region))
    error_message = "Region must be a valid AWS region identifier."
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and logging"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = true
  nullable    = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

variable "enable_encryption" {
  description = "Enable encryption at rest for all data services"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for databases and storage"
  type        = bool
  default     = false
  nullable    = false
}

variable "cost_center" {
  description = "Cost center code for billing allocation"
  type        = string
  default     = "infrastructure"
  nullable    = false
}

variable "owner" {
  description = "Owner or team responsible for infrastructure"
  type        = string
  default     = "devops"
  nullable    = false
}

variable "managed_by" {
  description = "Tool used to manage this infrastructure"
  type        = string
  default     = "opentofu"
  nullable    = false
}

variable "neon_api_key" {
  description = "Neon API key for serverless database provisioning"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "neon_region_map" {
  description = "Mapping of AWS regions to Neon regions"
  type        = map(string)
  default = {
    "us-east-1"      = "aws-us-east-1"
    "us-west-2"      = "aws-us-west-2"
    "eu-west-1"      = "aws-eu-west-1"
    "eu-central-1"   = "aws-eu-central-1"
    "ap-southeast-1" = "aws-ap-southeast-1"
    "ap-northeast-1" = "aws-ap-northeast-1"
  }
  nullable = false
}

variable "turso_api_token" {
  description = "Turso API token for tenant database provisioning"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "turso_auth_token" {
  description = "Turso auth token for CLI operations (stored in SSM by module)"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "turso_organization" {
  description = "Turso organization name"
  type        = string
  nullable    = false
}

variable "turso_group" {
  description = "Turso database group/organization"
  type        = string
  default     = "default"
  nullable    = false
}

variable "app_key" {
  description = "Application APP_KEY (Laravel). Will be stored in SSM by ssm module."
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_password" {
  description = "Redis password for cache/queue. Will be stored in SSM by ssm module."
  type        = string
  sensitive   = true
  default     = ""
}

# Additional backend secrets from backend/.env.example
variable "db_password" {
  description = "PostgreSQL DB password for the backend (DB_PASSWORD)"
  type        = string
  sensitive   = true
}

variable "pgadmin_default_password" {
  description = "Default password for pgAdmin (PGADMIN_DEFAULT_PASSWORD)"
  type        = string
  sensitive   = true
}

variable "tenant_db_auth_token" {
  description = "Tenant database JWT auth token (TENANT_DB_AUTH_TOKEN)"
  type        = string
  sensitive   = true
}

variable "tenant_db_encryption_key" {
  description = "LibSQL / tenant DB encryption key (TENANT_DB_ENCRYPTION_KEY)"
  type        = string
  sensitive   = true
}

variable "mail_password" {
  description = "SMTP mail password for application email delivery (MAIL_PASSWORD)"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID used by backend services (AWS_ACCESS_KEY_ID)"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key used by backend services (AWS_SECRET_ACCESS_KEY)"
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret (GOOGLE_CLIENT_SECRET)"
  type        = string
  sensitive   = true
}

variable "stripe_secret" {
  description = "Stripe secret key for payments (STRIPE_SECRET)"
  type        = string
  sensitive   = true
}

variable "stripe_client_id" {
  description = "Stripe client ID for Connect (STRIPE_CLIENT_ID)"
  type        = string
  sensitive   = true
}

variable "stripe_connect_webhook_secret" {
  description = "Stripe Connect webhook signing secret (STRIPE_CONNECT_WEBHOOK_SECRET)"
  type        = string
  sensitive   = true
}

variable "kv_store_api_token" {
  description = "API token for the KV store service (KV_STORE_API_TOKEN)"
  type        = string
  sensitive   = true
}

variable "kms_key_id" {
  description = "Optional KMS key ARN used for encrypting SSM SecureString parameters"
  type        = string
  default     = ""
}

# Networking variables
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  nullable    = false
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  nullable    = false
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  nullable    = false
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway for private subnets"
  type        = bool
  default     = true
  nullable    = false
}

# Security variables
variable "app_ports" {
  description = "List of application ports to allow to EC2 instances"
  type        = list(number)
  default     = [3000, 8000, 80, 443]
  nullable    = false
}

# Cloudflare Load Balancer variables
variable "renderer_origin_ip" {
  description = "Origin IP for renderer wildcard DNS record"
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "Health check path for API"
  type        = string
  default     = "/health"
}

variable "notification_email" {
  description = "Email for Cloudflare notifications"
  type        = string
  default     = ""
}

variable "enable_cloudflare_waf" {
  description = "Enable Cloudflare Web Application Firewall"
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

variable "enable_cloudflare_lb" {
  description = "Enable Cloudflare Load Balancer"
  type        = bool
  default     = true
}

variable "enable_strict_security" {
  description = "Whether to enable strict security rules (production) or relaxed rules (development)"
  type        = bool
  default     = false
  nullable    = false
}

# Storage variables
variable "enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for static assets"
  type        = bool
  default     = false
  nullable    = false
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the logs bucket"
  type        = number
  default     = 30
  nullable    = false
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
  nullable    = false
}

# Compute variables
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.micro"
  nullable    = false
}

variable "ami_id" {
  description = "AMI ID for the instances"
  type        = string
  default     = "ami-0abcdef1234567890" # Default placeholder - should be set per region
  nullable    = false
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = ""
  nullable    = false
}

variable "min_size" {
  description = "Minimum size of the Auto Scaling Group"
  type        = number
  default     = 1
  nullable    = false
}

variable "max_size" {
  description = "Maximum size of the Auto Scaling Group"
  type        = number
  default     = 6
  nullable    = false
}

variable "desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  type        = number
  nullable    = false
}

variable "scaling_cpu_threshold" {
  description = "CPU threshold percentage that triggers scale up"
  type        = number
  default     = 70
  nullable    = false
}

variable "scaling_down_cpu_threshold" {
  description = "CPU threshold percentage that triggers scale down"
  type        = number
  default     = 30
  nullable    = false
}

variable "detailed_monitoring" {
  description = "Enable detailed monitoring for instances"
  type        = bool
  default     = true
  nullable    = false
}

variable "ebs_optimized" {
  description = "Enable EBS optimization for instances"
  type        = bool
  default     = true
  nullable    = false
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 30
  nullable    = false
}

variable "root_volume_type" {
  description = "Type of the root volume"
  type        = string
  default     = "gp3"
  nullable    = false
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "paymentform-cluster"
  nullable    = false
}

locals {
  standard_tags = merge(
    var.common_tags,
    {
      Project    = var.project_name
      ManagedBy  = var.managed_by
      CreatedAt  = timestamp()
      CostCenter = var.cost_center
      Owner      = var.owner
    }
  )

  # Naming conventions for resources
  resource_prefix = "${var.project_name}-${var.environment}"

  # Environment-specific settings
  is_prod    = var.environment == "prod"
  is_sandbox = var.environment == "sandbox"
  is_dev     = var.environment == "dev"
}

# AWS Amplify configuration
variable "enable_amplify" {
  description = "Enable AWS Amplify for renderer and client deployments"
  type        = bool
  default     = false
}

variable "renderer_repository_url" {
  description = "Git repository URL for renderer application"
  type        = string
  default     = ""
}

variable "renderer_branch_name" {
  description = "Branch name to deploy for renderer"
  type        = string
  default     = "main"
}

variable "renderer_env_vars" {
  description = "Environment variables for renderer application"
  type        = map(string)
  default     = {}
}

variable "renderer_custom_domain" {
  description = "Custom domain for renderer (optional)"
  type        = string
  default     = ""
}

variable "renderer_subdomain_prefix" {
  description = "Subdomain prefix for renderer"
  type        = string
  default     = ""
}

variable "client_repository_url" {
  description = "Git repository URL for client application"
  type        = string
  default     = ""
}

variable "client_branch_name" {
  description = "Branch name to deploy for client"
  type        = string
  default     = "main"
}

variable "client_env_vars" {
  description = "Environment variables for client application"
  type        = map(string)
  default     = {}
}

variable "client_custom_domain" {
  description = "Custom domain for client (optional)"
  type        = string
  default     = ""
}

variable "client_subdomain_prefix" {
  description = "Subdomain prefix for client"
  type        = string
  default     = ""
}

variable "amplify_access_token" {
  description = "GitHub/GitLab personal access token for private repositories"
  type        = string
  sensitive   = true
  default     = ""
}
