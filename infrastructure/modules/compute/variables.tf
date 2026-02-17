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
variable "image_registry_type" {
  description = "Type of image registry: local | ecr | ghcr"
  type        = string
  default     = "local"
}

variable "ecr_account_id" {
  description = "AWS account ID for ECR image registry"
  type        = string
  default     = ""
}

variable "ecr_region" {
  description = "AWS region for ECR"
  type        = string
  default     = "us-east-1"
}

variable "region" {
  description = "AWS region used by the compute module"
  type        = string
  nullable    = false
}