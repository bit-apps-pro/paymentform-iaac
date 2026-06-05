variable "enabled" {
  description = "Whether to create the Hetzner admin server resources"
  type        = bool
  default     = true
}

variable "environment" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "location" {
  description = "Hetzner datacenter location (e.g. hel1, sin1, fsn1)"
  type        = string
}

variable "server_type" {
  description = "Hetzner server type (e.g. cx22, cpx21, ccx13)"
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "Hetzner OS image (e.g. ubuntu-24.04)"
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_key_id" {
  description = "Hetzner SSH key ID to attach to the server."
  type        = string
  default     = ""
}

variable "os_username" {
  description = "OS username to create on the server for SSH access"
  type        = string
  default     = "paymentform"
}

variable "os_user_public_key" {
  description = "SSH public key to add to the OS user's authorized_keys. Empty string skips user creation."
  type        = string
  default     = ""
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key used by the null_resource to push updated userdata without server replacement. Empty string skips the SSH apply step."
  type        = string
  default     = ""
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access (admin IPs only)"
  type        = list(string)
  default     = []
}

variable "ghcr_username" {
  type = string
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "admin_image" {
  description = "Container image for the admin app (e.g. ghcr.io/bit-apps-pro/paymentform-admin:latest)"
  type        = string
}

variable "backend_image" {
  description = "Container image for the backend app, used by the SQS-overflow queue worker co-deployed on the admin host (e.g. ghcr.io/bit-apps-pro/paymentform-backend:latest)"
  type        = string
}

variable "backend_queue_container_env_vars" {
  description = "Full Laravel env map (merged backend + Hetzner overrides) for the admin-host backend-queue overflow container. Rendered to /opt/app/backend-queue.env and consumed by the backend-queue service via env_file."
  type        = map(any)
  sensitive   = true
}

variable "traefik_host" {
  description = "Primary domain for Traefik routing (e.g. paymentform.io)"
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME certificate registration"
  type        = string
}

variable "valkey_password" {
  description = "Password for the local Valkey instance"
  type        = string
  sensitive   = true
}

variable "local_db_database" {
  description = "Database name for the local PostgreSQL instance (admin's own data)"
  type        = string
  default     = "paymentform_admin"
}

variable "local_db_username" {
  description = "Username for the local PostgreSQL admin role"
  type        = string
  default     = "admin"
}

variable "local_db_password" {
  description = "Password for the local PostgreSQL admin role"
  type        = string
  sensitive   = true
}

variable "backup_replication_password" {
  description = "Password for the local barman_replica role used by barman to perform pg_basebackup against the local postgres"
  type        = string
  sensitive   = true
}

variable "backup_bucket_name" {
  description = "R2 bucket name for admin DB barman-cloud-backup artifacts"
  type        = string
}

variable "backup_bucket_endpoint" {
  description = "R2 S3-compatible endpoint URL (e.g. https://<account_id>.r2.cloudflarestorage.com)"
  type        = string
}

variable "backup_bucket_access_key_id" {
  description = "R2 access key ID for the admin DB backup bucket"
  type        = string
  sensitive   = true
}

variable "backup_bucket_access_key" {
  description = "R2 secret access key for the admin DB backup bucket"
  type        = string
  sensitive   = true
}

variable "backup_server_name" {
  description = "Barman server identifier used as the subpath/server-name inside the bucket"
  type        = string
  default     = "admin-postgres"
}

variable "backup_schedule" {
  description = "Cron schedule expression for the weekly barman-cloud-backup (default: Sunday 03:00 UTC)"
  type        = string
  default     = "0 3 * * 0"
}

variable "admin_container_env_vars" {
  description = "Environment variables for the admin Laravel container (.env)"
  type        = map(string)
  default     = {}
}

variable "network_id" {
  description = "Hetzner private network ID to attach this server to. Empty string disables attachment."
  type        = string
  default     = ""
}

variable "deploy_script_content" {
  description = "Full text of admin/.github/scripts/deploy-hetzner.sh"
  type        = string
}

variable "compose_file_content" {
  description = "Full text of admin/docker-compose.yml"
  type        = string
}

variable "standard_tags" {
  type    = map(string)
  default = {}
}
