variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "backend_image" {
  description = "Docker image for the backend service"
  type        = string
  default     = "paymentform/backend"
}

variable "backend_version" {
  description = "Version tag for the backend image"
  type        = string
  default     = "latest"
}

variable "backend_cpu" {
  description = "CPU units for the backend task"
  type        = string
  default     = "512"
}

variable "backend_memory" {
  description = "Memory for the backend task"
  type        = string
  default     = "1024"
}

variable "backend_instance_count" {
  description = "Number of backend instances to run"
  type        = number
  default     = 2
}

variable "primary_db_endpoint" {
  description = "Endpoint for the primary database"
  type        = string
}

variable "db_database" {
  description = "Database name"
  type        = string
  default     = "shopper_backend"
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for storage"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
}

variable "app_key_secret_arn" {
  description = "ARN of the secret containing the Laravel APP_KEY"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}