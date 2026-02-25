output "app_key_path" {
  description = "SSM parameter path for APP_KEY"
  value       = aws_ssm_parameter.app_key.name
}

output "redis_password_path" {
  description = "SSM parameter path for REDIS_PASSWORD"
  value       = aws_ssm_parameter.redis_password.name
}

output "turso_auth_token_path" {
  description = "SSM parameter path for TURSO_AUTH_TOKEN"
  value       = aws_ssm_parameter.turso_auth_token.name
}

output "turso_api_token_path" {
  description = "SSM parameter path for TURSO_API_TOKEN"
  value       = length(aws_ssm_parameter.turso_api_token) > 0 ? aws_ssm_parameter.turso_api_token[0].name : ""
}

output "db_password_ssm_path" {
  description = "SSM parameter path for DB_PASSWORD"
  value       = aws_ssm_parameter.db_password.name
}

output "pgadmin_default_password_ssm_path" {
  description = "SSM parameter path for PGADMIN_DEFAULT_PASSWORD"
  value       = aws_ssm_parameter.pgadmin_default_password.name
}

output "tenant_db_auth_token_ssm_path" {
  description = "SSM parameter path for TENANT_DB_AUTH_TOKEN"
  value       = aws_ssm_parameter.tenant_db_auth_token.name
}

output "tenant_db_encryption_key_ssm_path" {
  description = "SSM parameter path for TENANT_DB_ENCRYPTION_KEY"
  value       = aws_ssm_parameter.tenant_db_encryption_key.name
}

output "mail_password_ssm_path" {
  description = "SSM parameter path for MAIL_PASSWORD"
  value       = aws_ssm_parameter.mail_password.name
}

output "aws_access_key_id_ssm_path" {
  description = "SSM parameter path for AWS_ACCESS_KEY_ID"
  value       = aws_ssm_parameter.aws_access_key_id.name
}

output "aws_secret_access_key_ssm_path" {
  description = "SSM parameter path for AWS_SECRET_ACCESS_KEY"
  value       = aws_ssm_parameter.aws_secret_access_key.name
}

output "google_client_secret_ssm_path" {
  description = "SSM parameter path for GOOGLE_CLIENT_SECRET"
  value       = aws_ssm_parameter.google_client_secret.name
}

output "stripe_secret_ssm_path" {
  description = "SSM parameter path for STRIPE_SECRET"
  value       = aws_ssm_parameter.stripe_secret.name
}

output "stripe_client_id_ssm_path" {
  description = "SSM parameter path for STRIPE_CLIENT_ID"
  value       = aws_ssm_parameter.stripe_client_id.name
}

output "stripe_connect_webhook_secret_ssm_path" {
  description = "SSM parameter path for STRIPE_CONNECT_WEBHOOK_SECRET"
  value       = aws_ssm_parameter.stripe_connect_webhook_secret.name
}

output "kv_store_api_token_ssm_path" {
  description = "SSM parameter path for KV_STORE_API_TOKEN"
  value       = aws_ssm_parameter.kv_store_api_token.name
}
