# Main OpenTofu configuration at root level
# This file sources the infrastructure modules from the infrastructure/ directory

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
  }

  # S3 backend configuration
  # Use -backend-config to specify environment-specific values
  backend "s3" {}
}

# Import infrastructure configurations
module "infrastructure" {
  source                = "./infrastructure"
  neon_database_url     = var.neon_database_url
  turso_api_token       = var.turso_api_token
  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id
  desired_capacity      = var.desired_capacity
  region                = var.region
  environment           = var.environment
  # Image registry (GHCR)
  ghcr_token = var.ghcr_token
  # Two-instance sizing
  backend_instance_type     = var.backend_instance_type
  renderer_instance_type    = var.renderer_instance_type
  backend_desired_capacity  = var.backend_desired_capacity
  renderer_desired_capacity = var.renderer_desired_capacity
  backend_ami_id            = var.backend_ami_id
  renderer_ami_id           = var.renderer_ami_id
  key_pair_name             = var.key_pair_name
  # Secrets
  google_client_secret          = var.google_client_secret
  tenant_db_encryption_key      = var.tenant_db_encryption_key
  stripe_secret                 = var.stripe_secret
  aws_secret_access_key         = var.aws_secret_access_key
  db_password                   = var.db_password
  stripe_client_id              = var.stripe_client_id
  pgadmin_default_password      = var.pgadmin_default_password
  tenant_db_auth_token          = var.tenant_db_auth_token
  aws_access_key_id             = var.aws_access_key_id
  turso_auth_token              = var.turso_auth_token
  mail_password                 = var.mail_password
  kv_store_api_token            = var.kv_store_api_token
  stripe_connect_webhook_secret = var.stripe_connect_webhook_secret
  # R2 Storage configuration
  r2_bucket_name        = var.r2_bucket_name
  r2_public_bucket_name = var.r2_public_bucket_name
  worker_enabled        = var.worker_enabled
  worker_route_pattern  = var.worker_route_pattern
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
output "tenants_kv_namespace_id" {
  description = "Cloudflare KV namespace ID for tenant storage"
  value       = module.infrastructure.tenants_kv_namespace_id
}

output "tenants_kv_namespace_title" {
  description = "Cloudflare KV namespace title"
  value       = module.infrastructure.tenants_kv_namespace_title
}
