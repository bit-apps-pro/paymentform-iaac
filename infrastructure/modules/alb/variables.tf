variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ID of the ALB security group"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  default     = ""  # Will be empty for dev environment
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the ALB"
  type        = bool
  default     = false
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "backend_health_check_path" {
  description = "Health check path for backend target group"
  type        = string
  default     = "/health"
}

variable "frontend_health_check_path" {
  description = "Health check path for frontend target group"
  type        = string
  default     = "/"
}

variable "route_to_frontend" {
  description = "Whether to route default requests to frontend"
  type        = bool
  default     = false
}

variable "enable_frontend_routing" {
  description = "Enable routing rules for frontend"
  type        = bool
  default     = true
}

variable "enable_backend_routing" {
  description = "Enable routing rules for backend"
  type        = bool
  default     = true
}

variable "frontend_path_patterns" {
  description = "Path patterns to route to frontend target group"
  type        = list(string)
  default     = ["/", "/app/*", "/static/*"]
}

variable "backend_path_patterns" {
  description = "Path patterns to route to backend target group"
  type        = list(string)
  default     = ["/api/*", "/admin/*", "/health"]
}

variable "log_retention_days" {
  description = "Number of days to retain ALB access logs"
  type        = number
  default     = 30
}

variable "enable_access_logs" {
  description = "Enable access logs for the ALB"
  type        = bool
  default     = true
}