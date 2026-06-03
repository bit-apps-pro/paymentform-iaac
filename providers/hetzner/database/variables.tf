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
  description = "Hetzner datacenter location (e.g. hel1, sin1)"
  type        = string
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "Hetzner OS image"
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  type    = string
  default = ""
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

variable "ssh_private_key_path" {
  description = "Path to SSH private key used by the null_resource to push updated userdata without server replacement. Empty string skips the SSH apply step."
  type        = string
  default     = ""
}

variable "volume_size_gb" {
  description = "Data volume size in GB"
  type        = number
  default     = 30
}

variable "primary_host" {
  description = "Hostname or IP of the Postgres primary (tunnel endpoint)"
  type        = string
}

variable "primary_port" {
  description = "Port of the Postgres primary"
  type        = number
  default     = 5432
}

variable "db_password" {
  description = "Password for the replicator user"
  type        = string
  sensitive   = true
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to connect to Postgres port 5432"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access (admin IPs only)"
  type        = list(string)
  default     = []
}

variable "backend_private_cidrs" {
  description = "CIDR blocks of backend servers allowed to connect to the replica"
  type        = list(string)
  default     = []
}

variable "backend_public_ipv4" {
  description = "Public IPv4 of the backend server. Used as fallback for DB firewall when backend_private_cidrs is empty."
  type        = string
  default     = ""
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

variable "enabled" {
  description = "Enable the Hetzner database replica server"
  type        = bool
  default     = true
}
