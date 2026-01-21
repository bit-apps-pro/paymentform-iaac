variable "aws_region" {
  description = "AWS region for the replica database"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_identifier" {
  description = "Identifier for the Aurora replica cluster"
  type        = string
  default     = "paymentform-replica-db"
}

variable "global_cluster_identifier" {
  description = "Identifier for the global cluster"
  type        = string
  default     = "paymentform-global-db"
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

variable "primary_cluster_arn" {
  description = "ARN of the primary cluster for replication"
  type        = string
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

variable "replica_instances" {
  description = "Number of replica instances"
  type        = number
  default     = 1
}

variable "enable_global_cluster" {
  description = "Enable global cluster for cross-region replication"
  type        = bool
  default     = true
}