resource "aws_ssm_parameter" "neon_database_url" {
  count       = var.neon_database_url != "" ? 1 : 0
  name        = "/app/${var.environment}/backend/DATABASE_URL"
  description = "Neon PostgreSQL connection string"
  type        = "SecureString"
  value       = var.neon_database_url
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "app_key" {
  name        = "/app/${var.environment}/backend/APP_KEY"
  description = "Laravel APP_KEY for backend"
  type        = "SecureString"
  value       = var.app_key
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "redis_password" {
  name        = "/app/${var.environment}/backend/REDIS_PASSWORD"
  description = "Redis password for backend"
  type        = "SecureString"
  value       = var.redis_password
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "turso_auth_token" {
  name        = "/app/${var.environment}/backend/TURSO_AUTH_TOKEN"
  description = "Turso auth token used for CLI operations"
  type        = "SecureString"
  value       = var.turso_auth_token
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "turso_api_token" {
  count       = var.turso_api_token != "" ? 1 : 0
  name        = "/app/${var.environment}/backend/TURSO_API_TOKEN"
  description = "Turso API token"
  type        = "SecureString"
  value       = var.turso_api_token
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/app/${var.environment}/backend/DB_PASSWORD"
  description = "PostgreSQL DB password for backend"
  type        = "SecureString"
  value       = var.db_password
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "pgadmin_default_password" {
  name        = "/app/${var.environment}/backend/PGADMIN_DEFAULT_PASSWORD"
  description = "pgAdmin default password"
  type        = "SecureString"
  value       = var.pgadmin_default_password
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "tenant_db_auth_token" {
  name        = "/app/${var.environment}/backend/TENANT_DB_AUTH_TOKEN"
  description = "Tenant DB JWT auth token"
  type        = "SecureString"
  value       = var.tenant_db_auth_token
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "tenant_db_encryption_key" {
  name        = "/app/${var.environment}/backend/TENANT_DB_ENCRYPTION_KEY"
  description = "LibSQL tenant DB encryption key"
  type        = "SecureString"
  value       = var.tenant_db_encryption_key
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "mail_password" {
  name        = "/app/${var.environment}/backend/MAIL_PASSWORD"
  description = "SMTP mail password for backend"
  type        = "SecureString"
  value       = var.mail_password
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "aws_access_key_id" {
  name        = "/app/${var.environment}/backend/AWS_ACCESS_KEY_ID"
  description = "AWS access key ID for backend"
  type        = "SecureString"
  value       = var.aws_access_key_id
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "aws_secret_access_key" {
  name        = "/app/${var.environment}/backend/AWS_SECRET_ACCESS_KEY"
  description = "AWS secret access key for backend"
  type        = "SecureString"
  value       = var.aws_secret_access_key
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "google_client_secret" {
  name        = "/app/${var.environment}/backend/GOOGLE_CLIENT_SECRET"
  description = "Google OAuth client secret"
  type        = "SecureString"
  value       = var.google_client_secret
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "stripe_secret" {
  name        = "/app/${var.environment}/backend/STRIPE_SECRET"
  description = "Stripe secret key"
  type        = "SecureString"
  value       = var.stripe_secret
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "stripe_client_id" {
  name        = "/app/${var.environment}/backend/STRIPE_CLIENT_ID"
  description = "Stripe client ID"
  type        = "SecureString"
  value       = var.stripe_client_id
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "stripe_connect_webhook_secret" {
  name        = "/app/${var.environment}/backend/STRIPE_CONNECT_WEBHOOK_SECRET"
  description = "Stripe Connect webhook secret"
  type        = "SecureString"
  value       = var.stripe_connect_webhook_secret
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "kv_store_api_token" {
  name        = "/app/${var.environment}/backend/KV_STORE_API_TOKEN"
  description = "KV store API token"
  type        = "SecureString"
  value       = var.kv_store_api_token
  overwrite   = true
  key_id      = var.kms_key_id
}

resource "aws_ssm_parameter" "ghcr_token" {
  count       = var.ghcr_token != "" ? 1 : 0
  name        = "/app/${var.environment}/backend/GHCR_TOKEN"
  description = "GitHub Container Registry token for Docker image pull"
  type        = "SecureString"
  value       = var.ghcr_token
  overwrite   = true
  key_id      = var.kms_key_id
}
