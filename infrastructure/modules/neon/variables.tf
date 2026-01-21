variable "neon_api_key" {
  description = "Neon API key for authentication"
  type        = string
  sensitive   = true
}

variable "neon_region" {
  description = "Neon region (aws-us-east-1, aws-eu-west-1, etc.)"
  type        = string
  default     = "aws-us-east-1"
  nullable    = false
}

variable "resource_prefix" {
  description = "Resource naming prefix"
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "standard_tags" {
  description = "Standard tags for resources"
  type        = map(string)
  default     = {}
  nullable    = false
}
