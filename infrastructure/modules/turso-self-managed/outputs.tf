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

output "tenant_db_token_ssm_path" {
  description = "SSM parameter path for tenant DB token"
  value       = "/app/${var.environment}/backend/TURSO_TENANTS_DB_TOKEN"
}

output "analytics_db_token_ssm_path" {
  description = "SSM parameter path for analytics DB token"
  value       = "/app/${var.environment}/backend/TURSO_ANALYTICS_DB_TOKEN"
}

output "backup_db_token_ssm_path" {
  description = "SSM parameter path for backup DB token"
  value       = "/app/${var.environment}/backend/TURSO_BACKUP_DB_TOKEN"
}

# Export database names for downstream modules
output "tenant_db_name" {
  description = "Turso tenant database name"
  value       = "${var.resource_prefix}-tenants"
}

output "analytics_db_name" {
  description = "Turso analytics database name"
  value       = "${var.resource_prefix}-analytics"
}

output "backup_db_name" {
  description = "Turso backup database name"
  value       = "${var.resource_prefix}-backup"
}