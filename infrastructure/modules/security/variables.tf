variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "app_ports" {
  description = "List of application ports to allow from ALB to ECS"
  type        = list(number)
  default     = [3000, 8000]
}

variable "neon_api_key_secret_arn" {
  description = "ARN of the Neon API key secret in AWS Secrets Manager"
  type        = string
  default     = ""
}

variable "turso_token_secret_arn" {
  description = "ARN of the Turso token secret in AWS Secrets Manager"
  type        = string
  default     = ""
}

variable "enable_strict_security" {
  description = "Whether to enable strict security rules (production) or relaxed rules (development)"
  type        = bool
  default     = false
}