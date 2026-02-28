# Cloudflare Container Module Variables
# Reusable module for deploying a single container

variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Containers permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for domain routing"
  type        = string
}

# Container Configuration
variable "container_name" {
  description = "Name of the container (e.g., client, renderer)"
  type        = string
}

variable "container_image" {
  description = "Container image URL (e.g., ghcr.io/org/image:tag)"
  type        = string
}

variable "container_enabled" {
  description = "Enable this container deployment"
  type        = bool
  default     = true
}

# Domain Configuration
variable "domain_name" {
  description = "Domain or subdomain for the container (e.g., app.sandbox.paymentform.io or *.sandbox.paymentform.io)"
  type        = string
}

variable "domain_proxied" {
  description = "Enable Cloudflare proxy for the domain"
  type        = bool
  default     = true
}

# Resource Allocation
variable "deployment_cpu" {
  description = "CPU allocation for container (e.g., 0.5, 1, 2)"
  type        = string
  default     = "0.5"
}

variable "deployment_memory_mb" {
  description = "Memory allocation in MB (e.g., 512, 1024, 2048)"
  type        = number
  default     = 512
}

variable "instance_min_count" {
  description = "Minimum number of container instances"
  type        = number
  default     = 1
}

variable "instance_max_count" {
  description = "Maximum number of container instances"
  type        = number
  default     = 3
}

# Environment Variables
variable "container_env_vars" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

# Registry Configuration
variable "registry_url" {
  description = "Container registry URL (e.g., ghcr.io)"
  type        = string
  default     = "ghcr.io"
}

variable "registry_username" {
  description = "Container registry username"
  type        = string
  default     = "x-access-token"
}

variable "registry_password" {
  description = "Container registry password or token"
  type        = string
  sensitive   = true
}
