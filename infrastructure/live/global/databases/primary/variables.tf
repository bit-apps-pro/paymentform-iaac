variable "aws_region" {
  description = "AWS region for the database"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_identifier" {
  description = "Identifier for the Aurora cluster"
  type        = string
  default     = "paymentform-primary-db"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "14.9"
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "shopper_backend"
}

variable "master_username" {
  description = "Master username for the database"
  type        = string
}

variable "master_password" {
  description = "Master password for the database"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be deployed"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "02:00-03:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window (UTC)"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "create_final_snapshot" {
  description = "Create a final snapshot when the cluster is deleted"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "instance_class" {
  description = "Instance class for the database"
  type        = string
  default     = "db.serverless"
}

variable "primary_instances" {
  description = "Number of primary instances"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum capacity for serverless v2"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Maximum capacity for serverless v2"
  type        = number
  default     = 16
}