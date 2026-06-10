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

variable "scaling_request_count_per_target" {
  description = "RequestCountPerTarget Sum (per 60s period) that triggers scale up. At 6 Octane workers × ~25 req/s/worker = ~150 req/s/target steady, so 9000/min = ~150 req/s sustained. Tune after load test."
  type        = number
  default     = 9000
}

variable "scaling_down_request_count_per_target" {
  description = "RequestCountPerTarget Sum (per 60s period) that triggers scale down. 1800/min = ~30 req/s/target — well below comfortable load."
  type        = number
  default     = 1800
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (used in CloudWatch metric dimensions). Get from aws_lb.arn_suffix attribute."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the ALB target group (used in CloudWatch metric dimensions). Get from aws_lb_target_group.arn_suffix."
  type        = string
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

variable "caddy_env_vars" {
  description = "Caddy-specific environment variables (ACME_EMAIL, CLOUDFLARE_API_TOKEN, CADDY_LOG_LEVEL, etc.)"
  type        = map(string)
  default     = {}
}

variable "ghcr_username" {
  description = "GitHub Container Registry username for pulling private images"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image name (e.g., ghcr.io/bit-apps-pro/paymentform-backend:latest)"
  type        = string
  default     = "ghcr.io/bit-apps-pro/paymentform-backend:latest"
}

variable "alb_target_group_arns" {
  description = "ARNs of the target groups to attach ASG instances to (supports multiple, e.g. HTTP + HTTPS)"
  type        = list(string)
  default     = []
}

variable "auto_ssl" {
  description = "Enable AUTO_SSL in Caddy (true = HTTPS with auto SSL, false = HTTP only)"
  type        = bool
  default     = true
}

variable "spot_instance_percentage" {
  description = "Percentage of instances to run as spot (0 = all on-demand, 100 = all spot). Use 0 for primary region, 80-100 for secondary regions."
  type        = number
  default     = 0
  validation {
    condition     = var.spot_instance_percentage >= 0 && var.spot_instance_percentage <= 100
    error_message = "spot_instance_percentage must be between 0 and 100."
  }
}

variable "spot_instance_types" {
  description = "Additional instance types for spot capacity pool diversity (fallback types besides var.instance_type)"
  type        = list(string)
  default     = []
}

variable "tunnel_token" {
  description = "Cloudflare Tunnel token for cloudflared sidecar. When set, cloudflared runs alongside the app container and traffic is routed via tunnel instead of direct NLB."
  type        = string
  default     = ""
  sensitive   = true
}

variable "on_demand_base_capacity" {
  description = "Minimum number of on-demand instances to maintain before spot instances are used"
  type        = number
  default     = 0
}

variable "on_demand_percentage_above_base_capacity" {
  description = "Percentage of on-demand instances for capacity above the base (0-100). 0 = all spot above base."
  type        = number
  default     = 100
  validation {
    condition     = var.on_demand_percentage_above_base_capacity >= 0 && var.on_demand_percentage_above_base_capacity <= 100
    error_message = "on_demand_percentage_above_base_capacity must be between 0 and 100."
  }
}

variable "spot_allocation_strategy" {
  description = "Strategy for allocating spot instances (capacity-optimized, lowest-price, diversified, capacity-optimized-prioritized)"
  type        = string
  default     = "capacity-optimized"
}

variable "capacity_rebalance" {
  description = "Whether to enable capacity rebalance to proactively replace instances at risk of interruption"
  type        = bool
  default     = false
}

variable "deploy_script_content" {
  description = "Content of the deploy script to execute on EC2 instances"
  type        = string
  default     = ""
}

# Sockudo runs inside the backend container alongside FrankenPHP/Octane and
# the supervised queue workers. start.sh renders /etc/sockudo/config.json
# from REVERB_APP_{ID,KEY,SECRET} at boot, so the host-side bind-mount and
# the associated valkey/reverb/sockudo_* inputs are no longer module
# concerns. They're still passed to the container through container_env_vars.
