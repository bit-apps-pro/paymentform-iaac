resource "aws_ssm_parameter" "app_key" {
  count       = var.app_key != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/APP_KEY"
  description = "Laravel APP_KEY for backend"
  type        = "SecureString"
  value       = var.app_key
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "redis_password" {
  count       = var.redis_password != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/REDIS_PASSWORD"
  description = "Redis password for backend"
  type        = "SecureString"
  value       = var.redis_password
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "turso_auth_token" {
  count       = var.turso_auth_token != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/TURSO_AUTH_TOKEN"
  description = "Turso auth token used for CLI operations"
  type        = "SecureString"
  value       = var.turso_auth_token
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_ssm_parameter" "db_password" {
  count       = var.db_password != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/DB_PASSWORD"
  description = "PostgreSQL DB password for backend"
  type        = "SecureString"
  value       = var.db_password
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "tenant_db_auth_token" {
  count       = var.tenant_db_auth_token != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/TENANT_DB_AUTH_TOKEN"
  description = "Tenant DB JWT auth token"
  type        = "SecureString"
  value       = var.tenant_db_auth_token
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "tenant_db_encryption_key" {
  count       = var.tenant_db_encryption_key != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/TENANT_DB_ENCRYPTION_KEY"
  description = "LibSQL tenant DB encryption key"
  type        = "SecureString"
  value       = var.tenant_db_encryption_key
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "mail_password" {
  count       = var.mail_password != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/MAIL_PASSWORD"
  description = "SMTP mail password for backend"
  type        = "SecureString"
  value       = var.mail_password
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "aws_access_key_id" {
  count       = var.aws_access_key_id != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/AWS_ACCESS_KEY_ID"
  description = "AWS access key ID for backend"
  type        = "SecureString"
  value       = var.aws_access_key_id
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "aws_secret_access_key" {
  count       = var.aws_secret_access_key != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/AWS_SECRET_ACCESS_KEY"
  description = "AWS secret access key for backend"
  type        = "SecureString"
  value       = var.aws_secret_access_key
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "google_client_secret" {
  count       = var.google_client_secret != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/GOOGLE_CLIENT_SECRET"
  description = "Google OAuth client secret"
  type        = "SecureString"
  value       = var.google_client_secret
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "stripe_secret" {
  count       = var.stripe_secret != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/STRIPE_SECRET"
  description = "Stripe secret key"
  type        = "SecureString"
  value       = var.stripe_secret
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "stripe_client_id" {
  count       = var.stripe_client_id != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/STRIPE_CLIENT_ID"
  description = "Stripe client ID"
  type        = "SecureString"
  value       = var.stripe_client_id
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "stripe_connect_webhook_secret" {
  count       = var.stripe_connect_webhook_secret != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/STRIPE_CONNECT_WEBHOOK_SECRET"
  description = "Stripe Connect webhook secret"
  type        = "SecureString"
  value       = var.stripe_connect_webhook_secret
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "kv_store_api_token" {
  count       = var.kv_store_api_token != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/KV_STORE_API_TOKEN"
  description = "KV store API token"
  type        = "SecureString"
  value       = var.kv_store_api_token
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "ghcr_token" {
  count       = var.ghcr_token != "" ? 1 : 0
  name        = "/paymentform/${var.environment}/backend/GHCR_TOKEN"
  description = "GitHub Container Registry token for Docker image pull"
  type        = "SecureString"
  value       = var.ghcr_token
  overwrite   = true
  key_id      = var.kms_key_id

  lifecycle {
    prevent_destroy = true
  }
}
