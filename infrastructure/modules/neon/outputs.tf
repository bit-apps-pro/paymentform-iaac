output "project_id" {
  description = "Neon project ID"
  value       = neon_project.main.id
}

output "database_host" {
  description = "Neon database host"
  value       = "${neon_project.main.id}.aws.neon.tech"
}

output "database_name" {
  description = "Neon database name"
  value       = neon_database.app.name
}

output "app_role_name" {
  description = "Application database role name"
  value       = neon_role.app.name
}

output "readonly_role_name" {
  description = "Read-only database role name"
  value       = neon_role.readonly.name
}

output "connection_string" {
  description = "Neon connection string template (replace <password>)"
  value       = "postgresql://${neon_role.app.name}:<password>@${neon_project.main.id}.aws.neon.tech/${neon_database.app.name}?sslmode=require"
  sensitive   = true
}
