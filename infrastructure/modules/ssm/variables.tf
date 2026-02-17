variable "environment" {
  description = "Deployment environment (dev, sandbox, prod)"
  type        = string
}

variable "app_key" {
  description = "Application APP_KEY (Laravel)"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis password for the cache/queue"
  type        = string
  sensitive   = true
}

variable "turso_auth_token" {
  description = "Turso auth token used for CLI operations"
  type        = string
  sensitive   = true
}

variable "turso_api_token" {
  description = "Turso API token"
  type        = string
  sensitive   = true
}

variable "kms_key_id" {
  description = "Optional KMS key ARN for SSM SecureString encryption (default: account-managed)"
  type        = string
  default     = ""
}

variable "db_password" {
  description = "PostgreSQL DB password for the backend"
  type        = string
  sensitive   = true
}

variable "pgadmin_default_password" {
  description = "Default password for pgAdmin"
  type        = string
  sensitive   = true
}

variable "tenant_db_auth_token" {
  description = "Tenant database JWT auth token used by tenant services"
  type        = string
  sensitive   = true
}

variable "tenant_db_encryption_key" {
  description = "LibSQL / tenant DB encryption key"
  type        = string
  sensitive   = true
}

variable "mail_password" {
  description = "SMTP mail password for application email delivery"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID used by backend services"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key used by backend services"
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
}

variable "stripe_secret" {
  description = "Stripe secret key for payments"
  type        = string
  sensitive   = true
}

variable "stripe_client_id" {
  description = "Stripe client ID (Connect apps)"
  type        = string
  sensitive   = true
}

variable "stripe_connect_webhook_secret" {
  description = "Stripe Connect webhook signing secret"
  type        = string
  sensitive   = true
}

variable "kv_store_api_token" {
  description = "API token for the KV store service"
  type        = string
  sensitive   = true
}
