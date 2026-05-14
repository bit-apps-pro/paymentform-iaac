variable "enabled" {
  description = "Whether to create the Hetzner server resources"
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
  description = "Hetzner server type (e.g. cx22, cx32, cpx21)"
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "Hetzner OS image (e.g. ubuntu-24.04)"
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  description = "SSH public key content. Empty string disables SSH key resource creation. Deprecated: use ssh_key_id instead."
  type        = string
  default     = ""
}

variable "ssh_key_id" {
  description = "Hetzner SSH key ID to attach to server. Takes precedence over ssh_public_key."
  type        = string
  default     = ""
}

variable "os_username" {
  description = "OS username to create on the server for SSH access (e.g. deploy, admin)"
  type        = string
  default     = "deploy"
}

variable "os_user_public_key" {
  description = "SSH public key to add to the OS user's authorized_keys. Empty string skips user creation."
  type        = string
  default     = ""
}

variable "ghcr_username" {
  type = string
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "container_image" {
  type = string
}

variable "service_type" {
  description = "Service type label (backend, renderer)"
  type        = string
  default     = "backend"
}

variable "container_env_vars" {
  description = "Environment variables passed to the container"
  type        = map(string)
  default     = {}
}

variable "backend_container_env_vars" {
  description = "Environment variables for backend container"
  type        = map(string)
  default     = {}
}

variable "valkey_password" {
  description = "Password for the local Valkey instance"
  type        = string
  sensitive   = true
  default     = ""
}

variable "valkey_memory_max" {
  description = "Valkey maxmemory (e.g. 512mb, 1gb)"
  type        = string
  default     = "512mb"
}

variable "network_id" {
  description = "Hetzner private network ID to attach this server to. Empty string disables attachment."
  type        = string
  default     = ""
}

variable "standard_tags" {
  type    = map(string)
  default = {}
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access (admin IPs only)"
  type        = list(string)
  default     = []
}

variable "cloudflare_cidrs" {
  description = "Cloudflare IP ranges for HTTP/HTTPS access. If empty, fetched dynamically from Cloudflare."
  type        = list(string)
  default     = []
}

variable "renderer_container_image" {
  description = "Container image for renderer service (optional, enables renderer if provided)"
  type        = string
  default     = ""
}

variable "renderer_container_env_vars" {
  description = "Environment variables for renderer container"
  type        = map(string)
  default     = {}
}

variable "traefik_host" {
  description = "Primary domain for Traefik routing (e.g. paymentform.io)"
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME certificate registration"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for connecting to Hetzner server and applying userdata updates. Leave empty to disable SSH-based updates."
  type        = string
  default     = ""
}

variable "deploy_script_content" {
  description = "Content of the deploy script to execute on Hetzner instances"
  type        = string
  default     = ""
}

variable "db_host" {
  description = "Direct PostgreSQL host (IP or hostname) for backend containers"
  type        = string
  default     = ""
}

variable "caddy_env_vars" {
  description = "Caddy-specific environment variables (TLS, Cloudflare tokens, etc.)"
  type        = map(string)
  default     = {}
}
