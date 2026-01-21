variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "renderer_image" {
  description = "Docker image for the renderer service"
  type        = string
  default     = "paymentform/renderer"
}

variable "renderer_version" {
  description = "Version tag for the renderer image"
  type        = string
  default     = "latest"
}

variable "renderer_cpu" {
  description = "CPU units for the renderer task"
  type        = string
  default     = "512"
}

variable "renderer_memory" {
  description = "Memory for the renderer task"
  type        = string
  default     = "1024"
}

variable "renderer_instance_count" {
  description = "Number of renderer instances to run"
  type        = number
  default     = 2
}

variable "api_url" {
  description = "URL of the backend API"
  type        = string
}

variable "frontend_domain" {
  description = "Domain for the frontend application"
  type        = string
}

variable "allow_origin_hosts" {
  description = "Allowed origin hosts for CORS"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}