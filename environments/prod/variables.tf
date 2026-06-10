# Production US Region Variables

variable "cloudflare_api_email" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}
variable "cloudflare_api_token_wildcard_dns" {
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

variable "backend_container_image" {
  type    = string
  default = "ghcr.io/bit-apps-pro/paymentform-backend:latest"
}

variable "renderer_container_image" {
  type    = string
  default = "ghcr.io/bit-apps-pro/paymentform-renderer:latest"
}

variable "admin_container_image" {
  description = "Container image for the admin app"
  type        = string
  default     = "ghcr.io/bit-apps-pro/paymentform-admin:latest"
}

variable "stripe_public_key" {
  type    = string
  default = ""
}

variable "ssl_storage_access_key_id" {
  type      = string
  sensitive = true
}

variable "ssl_storage_secret_access_key" {
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

variable "valkey_password" {
  description = "Password for the local Valkey instance on the Hetzner admin server"
  type        = string
  sensitive   = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "admin_db_password" {
  description = "Password for the paymentform_admin user (used by Hetzner admin app to connect to primary DB)"
  type        = string
  sensitive   = true
}

variable "admin_local_db_password" {
  description = "Password for the admin app's LOCAL PostgreSQL instance (the `admin` superuser of paymentform_admin DB running on the Hetzner admin server)"
  type        = string
  sensitive   = true
}

variable "admin_backup_replication_password" {
  description = "Password for the `barman_replica` role on the LOCAL admin PostgreSQL. Used by barman-cloud-backup (running on the host) to perform pg_basebackup streaming."
  type        = string
  sensitive   = true
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
variable "mail_username" {
  type      = string
  sensitive = true
}

variable "mail_host" {
  type = string
}

variable "upload_storage_access_key_id" {
  type      = string
  sensitive = true
}

variable "upload_storage_secret_access_key" {
  type      = string
  sensitive = true
}

variable "upload_storage_access_key_id_eu" {
  description = "R2 API access key ID for EU upload storage bucket"
  type        = string
  sensitive   = true
}

variable "upload_storage_secret_access_key_eu" {
  description = "R2 API secret access key for EU upload storage bucket"
  type        = string
  sensitive   = true
}

variable "upload_storage_access_key_id_ap" {
  description = "R2 API access key ID for AP upload storage bucket"
  type        = string
  sensitive   = true
}

variable "upload_storage_secret_access_key_ap" {
  description = "R2 API secret access key for AP upload storage bucket"
  type        = string
  sensitive   = true
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
  description = "AMI ID for PostgreSQL instances in us-east-1"
  type        = string
  default     = ""
}

variable "valkey_ami_id" {
  description = "AMI ID for Valkey instances in us-east-1"
  type        = string
  default     = ""
}

variable "hetzner_api_token" {
  type      = string
  sensitive = true
}

variable "hetzner_ssh_public_key" {
  description = "SSH public key content for Hetzner VMs"
  type        = string
  default     = ""
}

variable "hetzner_ssh_key_name" {
  description = "Name of existing SSH key in Hetzner dashboard (takes precedence over creating new key)"
  type        = string
  default     = ""
}

variable "hetzner_ssh_private_key_path" {
  description = "Path to SSH private key for Hetzner servers. Used to apply userdata updates without recreation. Leave empty to disable."
  type        = string
  default     = ""
}

variable "hetzner_server_type" {
  description = "Hetzner server type for backend VMs (e.g. cx22, cpx21)"
  type        = string
  default     = "cx22"
}

variable "hetzner_db_server_type" {
  description = "Hetzner server type for DB replica VMs (e.g. cx22, cpx21)"
  type        = string
  default     = "cx22"
}

variable "backup_storage_access_key_id" {
  description = "R2 access key for pgbackrest backups"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_storage_access_key" {
  description = "R2 secret key for pgbackrest backups"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_storage_bucket_name" {
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
  description = "List of read replica endpoints (for EU/AU)"
  type        = list(string)
  default     = []
}

variable "peer_vpc_ids" {
  description = "List of peer VPC IDs for VPC peering (one per peer region)"
  type        = list(string)
  default     = []
}

variable "peer_route_table_ids" {
  description = "List of peer VPC route table IDs"
  type        = list(string)
  default     = []
}

variable "peer_vpc_cidrs" {
  description = "List of peer VPC CIDRs (must match peer_vpc_ids order)"
  type        = list(string)
  default     = []
}

variable "peer_regions" {
  description = "List of AWS regions for peer VPCs"
  type        = list(string)
  default     = []
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN for ALB HTTPS listener"
  type        = string
  default     = ""
}

variable "auto_ssl" {
  description = "Enable AUTO_SSL in Caddy (true = HTTPS, false = HTTP only)"
  type        = bool
  default     = true
}

variable "alert_webhook_url" {
  description = "HTTP(S) endpoint to POST to when all NLB targets remain unhealthy for 5 minutes"
  type        = string
  sensitive   = true
  default     = ""
}

variable "reverb_app_id" {
  description = "Pusher-protocol app id shared by Laravel broadcasts (REVERB_APP_ID) and the Sockudo sidecar's app_manager."
  type        = string
  default     = "1e1593236fab"
}

variable "reverb_app_key" {
  description = "Reverb app key for WebSocket broadcasting"
  type        = string
  sensitive   = true
}

variable "reverb_app_secret" {
  description = "Reverb app secret for WebSocket broadcasting"
  type        = string
  sensitive   = true
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to Hetzner instances (admin IPs only)"
  type        = list(string)
  default     = []
}

variable "traefik_host" {
  description = "Primary domain for Traefik routing on Hetzner backends (e.g. paymentform.io)"
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME certificate registration on Hetzner backends"
  type        = string
  default     = ""
}

variable "status_admin_token" {
  description = "Admin token for status page incident API authentication"
  type        = string
  sensitive   = true
}

variable "status_log_ingest_token" {
  description = "Write-only token shared with the backend to POST logs to status.paymentform.io/api/logs"
  type        = string
  sensitive   = true
}

variable "status_admin_allowed_countries" {
  description = "CSV of ISO country codes allowed to reach status.paymentform.io/admin/*. Empty = unrestricted."
  type        = string
  default     = "BD"
}

variable "status_admin_allowed_ips" {
  description = "CSV of IPv4 addresses and CIDRs allowed to reach status.paymentform.io/admin/*. Empty = unrestricted."
  type        = string
  default     = ""
}

# ----------------------------------------------------------------------------
# Renderer static-asset CDN (static.paymentform.io)
# ----------------------------------------------------------------------------
variable "renderer_static_cdn_domain" {
  description = "Public hostname for the renderer static-asset CDN. Inlined into the renderer build as NEXT_PUBLIC_CDN_URL, so changing it after rollout requires rebuilding the image."
  type        = string
  default     = "static.paymentform.io"
}

variable "renderer_static_cors_origins" {
  description = "Allowed Origin values for CORS GET/HEAD on the renderer static bucket. Defaults to `[*]` because tenant canonical hostnames are unknown at apply time and the assets are public."
  type        = list(string)
  default     = ["*"]
}

variable "admin_backend_api_token" {
  description = "API token for the admin app to authenticate with the backend API. Should be a long random string."
  type        = string
  sensitive   = true
} 