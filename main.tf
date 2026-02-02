# Main OpenTofu configuration at root level
# This file sources the infrastructure modules from the infrastructure/ directory

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "0.13.0"
    }
    turso = {
      source  = "celest-dev/turso"
      version = "0.2.3"
    }
  }
}

# Import infrastructure configurations
module "infrastructure" {
  source               = "./infrastructure"
  neon_api_key         = var.neon_api_key
  turso_api_token      = var.turso_api_token
  cloudflare_api_token = var.cloudflare_api_token
  cloudflare_zone_id   = var.cloudflare_zone_id
  desired_capacity     = var.desired_capacity
  region               = var.region
  environment          = var.environment
}

# Re-export all infrastructure outputs
output "resource_prefix" {
  description = "Standard prefix used for resource naming"
  value       = module.infrastructure.resource_prefix
}

output "standard_tags" {
  description = "Standard tags applied to all resources"
  value       = module.infrastructure.standard_tags
}

output "environment" {
  description = "Current deployment environment"
  value       = module.infrastructure.environment
}

output "region" {
  description = "Deployed region"
  value       = module.infrastructure.region
}

output "project_name" {
  description = "Project name"
  value       = module.infrastructure.project_name
}
output "database_host" {
  description = "Neon database host"
  value       = module.infrastructure.database_host
}

output "database_name" {
  description = "Neon database name"
  value       = module.infrastructure.database_name
}

output "database_app_role" {
  description = "Database application role"
  value       = module.infrastructure.database_app_role
}

output "neon_project_id" {
  description = "Neon project ID"
  value       = module.infrastructure.neon_project_id
}

output "neon_connection_string" {
  description = "Neon connection string (replace <password> with actual password)"
  value       = module.infrastructure.neon_connection_string
  sensitive   = true
}
output "tenant_db_url" {
  description = "Turso tenant database connection URL"
  value       = module.infrastructure.tenant_db_url
  sensitive   = true
}

output "tenant_db_name" {
  description = "Turso tenant database name"
  value       = module.infrastructure.tenant_db_name
}

output "analytics_db_url" {
  description = "Turso analytics database connection URL"
  value       = module.infrastructure.analytics_db_url
  sensitive   = true
}

output "analytics_db_name" {
  description = "Turso analytics database name"
  value       = module.infrastructure.analytics_db_name
}

output "backup_db_url" {
  description = "Turso backup database connection URL"
  value       = module.infrastructure.backup_db_url
  sensitive   = true
}

output "backup_db_name" {
  description = "Turso backup database name"
  value       = module.infrastructure.backup_db_name
}
