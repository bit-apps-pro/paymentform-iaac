output "app_key_path" {
  description = "SSM parameter path for APP_KEY"
  value       = length(aws_ssm_parameter.app_key) > 0 ? aws_ssm_parameter.app_key[0].name : ""
}

output "redis_password_path" {
  description = "SSM parameter path for REDIS_PASSWORD"
  value       = length(aws_ssm_parameter.redis_password) > 0 ? aws_ssm_parameter.redis_password[0].name : ""
}

output "turso_auth_token_path" {
  description = "SSM parameter path for TURSO_AUTH_TOKEN"
  value       = length(aws_ssm_parameter.turso_auth_token) > 0 ? aws_ssm_parameter.turso_auth_token[0].name : ""
}

output "db_password_ssm_path" {
  description = "SSM parameter path for DB_PASSWORD"
  value       = length(aws_ssm_parameter.db_password) > 0 ? aws_ssm_parameter.db_password[0].name : ""
}

output "tenant_db_auth_token_ssm_path" {
  description = "SSM parameter path for TENANT_DB_AUTH_TOKEN"
  value       = length(aws_ssm_parameter.tenant_db_auth_token) > 0 ? aws_ssm_parameter.tenant_db_auth_token[0].name : ""
}

output "tenant_db_encryption_key_ssm_path" {
  description = "SSM parameter path for TENANT_DB_ENCRYPTION_KEY"
  value       = length(aws_ssm_parameter.tenant_db_encryption_key) > 0 ? aws_ssm_parameter.tenant_db_encryption_key[0].name : ""
}

output "mail_password_ssm_path" {
  description = "SSM parameter path for MAIL_PASSWORD"
  value       = length(aws_ssm_parameter.mail_password) > 0 ? aws_ssm_parameter.mail_password[0].name : ""
}

output "aws_access_key_id_ssm_path" {
  description = "SSM parameter path for AWS_ACCESS_KEY_ID"
  value       = length(aws_ssm_parameter.aws_access_key_id) > 0 ? aws_ssm_parameter.aws_access_key_id[0].name : ""
}

output "aws_secret_access_key_ssm_path" {
  description = "SSM parameter path for AWS_SECRET_ACCESS_KEY"
  value       = length(aws_ssm_parameter.aws_secret_access_key) > 0 ? aws_ssm_parameter.aws_secret_access_key[0].name : ""
}

output "google_client_secret_ssm_path" {
  description = "SSM parameter path for GOOGLE_CLIENT_SECRET"
  value       = length(aws_ssm_parameter.google_client_secret) > 0 ? aws_ssm_parameter.google_client_secret[0].name : ""
}

output "stripe_secret_ssm_path" {
  description = "SSM parameter path for STRIPE_SECRET"
  value       = length(aws_ssm_parameter.stripe_secret) > 0 ? aws_ssm_parameter.stripe_secret[0].name : ""
}

output "stripe_client_id_ssm_path" {
  description = "SSM parameter path for STRIPE_CLIENT_ID"
  value       = length(aws_ssm_parameter.stripe_client_id) > 0 ? aws_ssm_parameter.stripe_client_id[0].name : ""
}

output "stripe_connect_webhook_secret_ssm_path" {
  description = "SSM parameter path for STRIPE_CONNECT_WEBHOOK_SECRET"
  value       = length(aws_ssm_parameter.stripe_connect_webhook_secret) > 0 ? aws_ssm_parameter.stripe_connect_webhook_secret[0].name : ""
}

output "kv_store_api_token_ssm_path" {
  description = "SSM parameter path for KV_STORE_API_TOKEN"
  value       = length(aws_ssm_parameter.kv_store_api_token) > 0 ? aws_ssm_parameter.kv_store_api_token[0].name : ""
}
