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

variable "use_cloudflare" {
  description = "Use Cloudflare-specific security rules (restrict to CF IPs only)"
  type        = bool
  default     = false
}

variable "enable_ssh_access" {
  description = "Enable SSH access to EC2 instances"
  type        = bool
  default     = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}