variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "resource_prefix" {
  type = string
}

variable "db_port" {
  description = "Local Postgres port to expose via the tunnel"
  type        = number
  default     = 5432
}

variable "zone_id" {
  description = "Cloudflare Zone ID for DNS records"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the tunnel hostname (e.g. paymentform.io). Empty disables DNS/Access."
  type        = string
  default     = ""
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to connect via Cloudflare Access (Hetzner public IPs, offices, etc). Optional; service token is primary auth."
  type        = list(string)
  default     = []
}

variable "session_duration" {
  description = "Cloudflare Access session duration"
  type        = string
  default     = "24h"
}

variable "service_token_duration" {
  description = "Lifetime of the Cloudflare Access service token (e.g. 8760h = 1 year)"
  type        = string
  default     = "8760h"
}
