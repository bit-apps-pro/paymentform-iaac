variable "cluster_identifier" {
  description = "Identifier for the Aurora cluster"
  type        = string
}

variable "engine" {
  description = "Database engine"
  type        = string
  default     = "aurora-postgresql"
}

variable "engine_version" {
  description = "Database engine version"
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

variable "subnet_ids" {
  description = "List of subnet IDs for the database"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the database"
  type        = list(string)
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "02:00-03:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "Instance class for the database"
  type        = string
  default     = "db.r6g.large"
}

# Aurora cluster
resource "aws_rds_cluster" "primary" {
  cluster_identifier           = var.cluster_identifier
  engine                       = var.engine
  engine_version               = var.engine_version
  database_name                = var.database_name
  master_username              = var.master_username
  master_password              = var.master_password
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  vpc_security_group_ids       = var.security_group_ids
  db_subnet_group_name         = aws_db_subnet_group.main.name
  skip_final_snapshot          = !var.deletion_protection
  deletion_protection          = var.deletion_protection
  storage_encrypted            = true

  tags = {
    Name        = "${var.cluster_identifier}-cluster"
    Environment = terraform.workspace
  }
}

# DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name        = "${var.cluster_identifier}-subnet-group"
    Environment = terraform.workspace
  }
}

# Primary instance
resource "aws_rds_cluster_instance" "primary" {
  identifier         = "${var.cluster_identifier}-primary"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  tags = {
    Name        = "${var.cluster_identifier}-primary-instance"
    Environment = terraform.workspace
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint of the primary cluster"
  value       = aws_rds_cluster.primary.endpoint
}

output "cluster_reader_endpoint" {
  description = "Reader endpoint of the primary cluster"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "cluster_resource_id" {
  description = "Resource ID of the cluster"
  value       = aws_rds_cluster.primary.cluster_resource_id
}