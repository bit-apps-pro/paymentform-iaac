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

# Neon Outputs
output "database_host" {
  description = "Neon database host"
  value       = module.neon_database.database_host
}

output "database_name" {
  description = "Neon database name"
  value       = module.neon_database.database_name
}

output "database_app_role" {
  description = "Database application role"
  value       = module.neon_database.app_role_name
}

output "neon_project_id" {
  description = "Neon project ID"
  value       = module.neon_database.project_id
}

output "neon_connection_string" {
  description = "Neon connection string (replace <password> with actual password)"
  value       = module.neon_database.connection_string
  sensitive   = true
}

# Turso Outputs
output "tenant_db_url" {
  description = "Turso tenant database connection URL"
  value       = module.turso_database.tenant_db_url
  sensitive   = true
}

output "tenant_db_name" {
  description = "Turso tenant database name"
  value       = module.turso_database.tenant_db_name
}

output "analytics_db_url" {
  description = "Turso analytics database connection URL"
  value       = module.turso_database.analytics_db_url
  sensitive   = true
}

output "analytics_db_name" {
  description = "Turso analytics database name"
  value       = module.turso_database.analytics_db_name
}

output "backup_db_url" {
  description = "Turso backup database connection URL"
  value       = module.turso_database.backup_db_url
  sensitive   = true
}

output "backup_db_name" {
  description = "Turso backup database name"
  value       = module.turso_database.backup_db_name
}
