# AWS Amplify module variables

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Access token for private repositories
variable "access_token" {
  description = "GitHub personal access token for private repositories"
  type        = string
  sensitive   = true
  default     = ""
}

# Renderer configuration
variable "renderer_repository_url" {
  description = "Git repository URL for renderer application"
  type        = string
}

variable "renderer_branch_name" {
  description = "Branch name to deploy for renderer"
  type        = string
  default     = "main"
}

variable "renderer_env_vars" {
  description = "Environment variables for renderer application"
  type        = map(string)
  default     = {}
}

variable "renderer_custom_domain" {
  description = "Custom domain for renderer (optional)"
  type        = string
  default     = ""
}

variable "renderer_subdomain_prefix" {
  description = "Subdomain prefix for renderer"
  type        = string
  default     = ""
}

# Client configuration
variable "client_repository_url" {
  description = "Git repository URL for client application"
  type        = string
}

variable "client_branch_name" {
  description = "Branch name to deploy for client"
  type        = string
  default     = "main"
}

variable "client_env_vars" {
  description = "Environment variables for client application"
  type        = map(string)
  default     = {}
}

variable "client_custom_domain" {
  description = "Custom domain for client (optional)"
  type        = string
  default     = ""
}

variable "client_subdomain_prefix" {
  description = "Subdomain prefix for client"
  type        = string
  default     = ""
}

# Amplify settings
variable "enable_auto_branch_creation" {
  description = "Enable automatic branch creation for new branches"
  type        = bool
  default     = false
}

variable "enable_branch_auto_build" {
  description = "Enable automatic builds for branches"
  type        = bool
  default     = true
}

variable "enable_branch_auto_deletion" {
  description = "Enable automatic deletion of branches when source branch is deleted"
  type        = bool
  default     = false
}
