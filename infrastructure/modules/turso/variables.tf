variable "turso_api_token" {
  description = "Turso API token for authentication"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "turso_organization" {
  description = "Turso organization name"
  type        = string
  nullable    = false
}

variable "turso_group" {
  description = "Turso database group/organization"
  type        = string
  default     = "default"
  nullable    = false
}

variable "resource_prefix" {
  description = "Resource naming prefix"
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "sandbox", "prod"], var.environment)
    error_message = "Environment must be dev, sandbox, or prod."
  }
}

variable "standard_tags" {
  description = "Standard tags for resources"
  type        = map(string)
  default     = {}
  nullable    = false
}
