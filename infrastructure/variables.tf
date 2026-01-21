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
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
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

variable "turso_group" {
  description = "Turso database group/organization"
  type        = string
  default     = "default"
  nullable    = false
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
  description = "List of application ports to allow from ALB to ECS"
  type        = list(number)
  default     = [3000, 8000]
  nullable    = false
}

variable "neon_api_key_secret_arn" {
  description = "ARN of the Neon API key secret in AWS Secrets Manager"
  type        = string
  default     = ""
  nullable    = false
}

variable "turso_token_secret_arn" {
  description = "ARN of the Turso token secret in AWS Secrets Manager"
  type        = string
  default     = ""
  nullable    = false
}

variable "enable_strict_security" {
  description = "Whether to enable strict security rules (production) or relaxed rules (development)"
  type        = bool
  default     = false
  nullable    = false
}

# ALB variables
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  default     = ""
  nullable    = false
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the ALB"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_alb_access_logs" {
  description = "Enable access logs for the ALB"
  type        = bool
  default     = true
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
  default     = "ami-0abcdef1234567890"  # Default placeholder - should be set per region
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
      Project     = var.project_name
      ManagedBy   = var.managed_by
      CreatedAt   = timestamp()
      CostCenter  = var.cost_center
      Owner       = var.owner
    }
  )

  # Naming conventions for resources
  resource_prefix = "${var.project_name}-${var.environment}"

  # Environment-specific settings
  is_prod    = var.environment == "prod"
  is_staging = var.environment == "staging"
  is_dev     = var.environment == "dev"
}
