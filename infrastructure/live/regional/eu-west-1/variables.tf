variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "client_image" {
  description = "Docker image for the client service"
  type        = string
  default     = "paymentform/client"
}

variable "client_version" {
  description = "Version tag for the client image"
  type        = string
  default     = "latest"
}

variable "client_cpu" {
  description = "CPU units for the client task"
  type        = string
  default     = "512"
}

variable "client_memory" {
  description = "Memory for the client task"
  type        = string
  default     = "1024"
}

variable "client_instance_count" {
  description = "Number of client instances to run"
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

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}