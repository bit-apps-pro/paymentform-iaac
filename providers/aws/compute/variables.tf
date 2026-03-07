variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Auto Scaling Group"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the instances"
  type        = string
  default     = "ami-0abcdef1234567890" # Default placeholder - should be set per region
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = ""
}

variable "min_size" {
  description = "Minimum size of the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum size of the Auto Scaling Group"
  type        = number
  default     = 6
}

variable "desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  type        = number
}

variable "scaling_cpu_threshold" {
  description = "CPU threshold percentage that triggers scale up"
  type        = number
  default     = 70
}

variable "scaling_down_cpu_threshold" {
  description = "CPU threshold percentage that triggers scale down"
  type        = number
  default     = 30
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "detailed_monitoring" {
  description = "Enable detailed monitoring for instances"
  type        = bool
  default     = true
}

variable "ebs_optimized" {
  description = "Enable EBS optimization for instances"
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 30
}

variable "root_volume_type" {
  description = "Type of the root volume"
  type        = string
  default     = "gp3"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "ecs_security_group_id" {
  description = "ID of the ECS security group"
  type        = string
}
variable "bucket_name" {
  description = "S3 uploads bucket name for this environment"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region used by the compute module"
  type        = string
  nullable    = false
}

variable "instance_prefix" {
  description = "Unique prefix for naming resources in this compute instance (avoids conflicts when module is used multiple times)"
  type        = string
  default     = ""
  # When empty, falls back to var.environment
}

variable "service_type" {
  description = "Service type to deploy: 'backend' (FrankenPHP + Caddy + Client) or 'renderer' (Next.js + Caddy)"
  type        = string
  validation {
    condition     = contains(["backend", "renderer"], var.service_type)
    error_message = "service_type must be either 'backend' or 'renderer'."
  }
}

variable "container_env_vars" {
  description = "Environment variables to pass to the container"
  type        = map(string)
  default     = {}
}

variable "db_read_replica_hosts" {
  description = "List of read replica host IPs/domains for PostgreSQL"
  type        = list(string)
  default     = []
}

variable "enable_pgbouncer" {
  description = "Enable PgBouncer for connection pooling and failover"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Database name for PgBouncer"
  type        = string
  default     = "shopper_backend"
}

variable "db_password" {
  description = "Database password for PgBouncer"
  type        = string
  sensitive   = true
  default     = ""
}

variable "container_image_tag" {
  description = "Container image tag to deploy (e.g., latest, v1.2.3, dev-abc123)"
  type        = string
  default     = "latest"
}

variable "alb_target_group_arn" {
  description = "ARN of the ALB target group to attach ASG instances to"
  type        = string
  default     = ""
}
