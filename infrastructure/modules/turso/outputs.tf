output "tenant_db_name" {
  description = "Turso tenant database name"
  value       = turso_database.tenant.name
}

output "tenant_db_url" {
  description = "Turso tenant database connection URL"
  value       = turso_database.tenant.connection_string
  sensitive   = true
}

output "analytics_db_name" {
  description = "Turso analytics database name"
  value       = turso_database.analytics.name
}

output "analytics_db_url" {
  description = "Turso analytics database connection URL"
  value       = turso_database.analytics.connection_string
  sensitive   = true
}

output "backup_db_name" {
  description = "Turso backup database name"
  value       = turso_database.backup.name
}

output "backup_db_url" {
  description = "Turso backup database connection URL"
  value       = turso_database.backup.connection_string
  sensitive   = true
}
