variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix used for naming Turso databases"
  type        = string
}

variable "turso_api_token" {
  description = "Turso API token"
  type        = string
  sensitive   = true
}

variable "turso_auth_token" {
  description = "Turso auth token used for CLI operations"
  type        = string
  sensitive   = true
}

variable "turso_organization" {
  description = "Turso organization"
  type        = string
}

variable "turso_group" {
  description = "Turso database group"
  type        = string
  default     = "default"
}

variable "region" {
  description = "AWS region used when storing SSM parameters via AWS CLI in the provisioner"
  type        = string
}

variable "kms_key_id" {
  description = "Optional KMS key ID to encrypt SSM parameters stored by the provisioner"
  type        = string
  default     = ""
}