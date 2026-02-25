# Root-level outputs for cross-module communication

output "resource_prefix" {
  description = "Standard prefix used for resource naming"
  value       = local.resource_prefix
}

output "standard_tags" {
  description = "Standard tags applied to all resources"
  value       = local.standard_tags
  sensitive   = false
}

output "environment" {
  description = "Current deployment environment"
  value       = var.environment
}

output "region" {
  description = "Deployed region"
  value       = var.region
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# Turso Outputs (SSM parameter paths only; secrets are NOT exposed)
output "tenant_db_ssm_path" {
  description = "SSM parameter path for tenant DB URL"
  value       = "/app/${var.environment}/backend/TURSO_TENANTS_DB_URL"
}

output "analytics_db_ssm_path" {
  description = "SSM parameter path for analytics DB URL"
  value       = "/app/${var.environment}/backend/TURSO_ANALYTICS_DB_URL"
}

output "backup_db_ssm_path" {
  description = "SSM parameter path for backup DB URL"
  value       = "/app/${var.environment}/backend/TURSO_BACKUP_DB_URL"
}

# Amplify Outputs
output "renderer_app_id" {
  description = "Amplify app ID for renderer"
  value       = var.enable_amplify ? module.amplify[0].renderer_app_id : null
}

output "renderer_default_domain" {
  description = "Default Amplify domain for renderer"
  value       = var.enable_amplify ? module.amplify[0].renderer_default_domain : null
}

output "renderer_branch_url" {
  description = "URL for renderer branch"
  value       = var.enable_amplify ? module.amplify[0].renderer_branch_url : null
}

output "renderer_custom_domain_url" {
  description = "Custom domain URL for renderer (if configured)"
  value       = var.enable_amplify ? module.amplify[0].renderer_custom_domain_url : null
}

output "client_app_id" {
  description = "Amplify app ID for client"
  value       = var.enable_amplify ? module.amplify[0].client_app_id : null
}

output "client_default_domain" {
  description = "Default Amplify domain for client"
  value       = var.enable_amplify ? module.amplify[0].client_default_domain : null
}

output "client_branch_url" {
  description = "URL for client branch"
  value       = var.enable_amplify ? module.amplify[0].client_branch_url : null
}

output "client_custom_domain_url" {
  description = "Custom domain URL for client (if configured)"
  value       = var.enable_amplify ? module.amplify[0].client_custom_domain_url : null
}

# Cloudflare KV Outputs
output "tenants_kv_namespace_id" {
  description = "Cloudflare KV namespace ID for tenant storage"
  value       = module.cloudflare.tenants_kv_namespace_id
}

output "tenants_kv_namespace_title" {
  description = "Cloudflare KV namespace title"
  value       = module.cloudflare.tenants_kv_namespace_title
}
