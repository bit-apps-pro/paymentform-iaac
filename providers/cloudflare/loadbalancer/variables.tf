variable "environment" {
  description = "Environment name"
  type        = string
}

variable "api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "lb_name" {
  description = "Load balancer hostname (e.g., api.paymentform.io)"
  type        = string
}

variable "description" {
  description = "Load balancer description"
  type        = string
  default     = "Multi-region load balancer"
}

variable "fallback_pool_id" {
  description = "Fallback pool ID"
  type        = string
}

variable "default_pool_ids" {
  description = "Default pool IDs"
  type        = list(string)
}

variable "region_pools" {
  description = "Map of region codes to pool IDs"
  type        = map(list(string))
  default     = {}
}

variable "pop_pools" {
  description = "Map of POP codes to pool IDs"
  type        = map(list(string))
  default     = {}
}

variable "steering_policy" {
  description = "Steering policy (geo, dynamic, etc)"
  type        = string
  default     = "geo"
}

variable "proxied" {
  description = "Proxied through Cloudflare"
  type        = bool
  default     = true
}

variable "ttl" {
  description = "DNS TTL"
  type        = number
  default     = 30
}

variable "standard_tags" {
  description = "Standard tags"
  type        = map(string)
  default     = {}
}
