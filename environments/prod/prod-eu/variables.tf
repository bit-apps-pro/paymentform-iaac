# Production EU Region Variables

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

variable "ghcr_username" {
  type = string
}

variable "ghcr_token" {
  type      = string
  sensitive = true
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

variable "client_container_image" {
  type    = string
  default = "ghcr.io/bit-apps-pro/paymentform-client:latest"
}

variable "renderer_container_image" {
  type    = string
  default = "ghcr.io/bit-apps-pro/paymentform-renderer:latest"
}

variable "stripe_public_key" {
  type    = string
  default = ""
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

variable "turso_org_slug" {
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

variable "google_client_id" {
  type = string
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

variable "postgres_ami_id" {
  description = "AMI ID for PostgreSQL instances (Ubuntu with PostgreSQL)"
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
  default     = ""
}

variable "r2_backup_secret_key" {
  description = "R2 secret key for pgbackrest backups"
  type        = string
  sensitive   = true
  default     = ""
}

variable "r2_backup_bucket_name" {
  description = "R2 bucket name for pgbackrest backups"
  type        = string
  default     = "prod-paymentform-backups"
}

variable "pgbackrest_cipher_pass" {
  description = "Encryption password for pgbackrest"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_read_replica_endpoints" {
  description = "List of additional read replica endpoints (for other regions)"
  type        = list(string)
  default     = []
}
