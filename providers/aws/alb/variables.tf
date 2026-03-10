variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}
variable "name" {
  description = "Instance name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ALB"
  type        = list(string)
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "target_port" {
  description = "Port for target group (EC2 backend port)"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/health"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN for HTTPS listener"
  type        = string
  default     = ""
}

variable "api_hostname" {
  description = "Hostname for API backend (e.g., api.paymentform.io)"
  type        = string
  default     = ""
}
