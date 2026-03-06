# Production Environment Variables

variable "cloudflare_api_email" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "ghcr_username" {
  type = string
}

variable "client_container_image" {
  type    = string
  default = "ghcr.io/your-org/paymentform-client:latest"
}

variable "backend_container_image" {
  type    = string
  default = "ghcr.io/your-org/paymentform-backend:latest"
}

variable "renderer_container_image" {
  type    = string
  default = "ghcr.io/your-org/paymentform-renderer:latest"
}

variable "r2_ssl_access_key_id" {
  type      = string
  sensitive = true
}

variable "r2_ssl_secret_access_key" {
  type      = string
  sensitive = true
}

variable "kv_store_api_token" {
  type      = string
  sensitive = true
}

variable "neon_database_url" {
  type      = string
  sensitive = true
}

variable "turso_auth_token" {
  type      = string
  sensitive = true
}

variable "turso_api_token" {
  type      = string
  sensitive = true
}

variable "turso_org_slug" {
  type = string
}

variable "db_host" {
  description = "Database host IP/hostname"
  type        = string
  default     = "10.0.1.50"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_database" {
  description = "Database name"
  type        = string
  default     = "shopper_backend"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "postgres"
}

variable "redis_host" {
  description = "Redis host IP/hostname"
  type        = string
  default     = "10.0.1.51"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "stripe_public_key" {
  type    = string
  default = ""
}

variable "google_client_id" {
  type = string
}

variable "app_key" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "pgadmin_default_password" {
  type      = string
  sensitive = true
}

variable "tenant_db_auth_token" {
  type      = string
  sensitive = true
}

variable "tenant_db_encryption_key" {
  type      = string
  sensitive = true
}

variable "mail_password" {
  type      = string
  sensitive = true
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

variable "stripe_secret" {
  type      = string
  sensitive = true
}

variable "stripe_client_id" {
  type      = string
  sensitive = true
}

variable "stripe_connect_webhook_secret" {
  type      = string
  sensitive = true
}

# Multi-Region Configuration
variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "postgres_ami_id" {
  description = "AMI ID for PostgreSQL instances"
  type        = string
  default     = ""
}

variable "valkey_ami_id" {
  description = "AMI ID for Valkey instances"
  type        = string
  default     = ""
}

variable "r2_backup_access_key" {
  description = "R2 access key for pgbackrest backups"
  type        = string
  sensitive   = true
}

variable "r2_backup_secret_key" {
  description = "R2 secret key for pgbackrest backups"
  type        = string
  sensitive   = true
}

variable "pgbackrest_cipher_pass" {
  description = "Encryption password for pgbackrest"
  type        = string
  sensitive   = true
}
