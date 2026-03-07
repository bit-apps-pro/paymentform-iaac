variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ami_id" {
  description = "AMI ID for PostgreSQL instances (e.g., Ubuntu with PostgreSQL)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for PostgreSQL instances (primary and replica)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for PostgreSQL instances"
  type        = string
}

variable "primary_instance_type" {
  description = "Instance type for PostgreSQL primary"
  type        = string
  default     = "t4g.micro"
}

variable "replica_instance_type" {
  description = "Instance type for PostgreSQL replica"
  type        = string
  default     = "t4g.micro"
}

variable "primary_volume_size" {
  description = "Root volume size for primary (GB)"
  type        = number
  default     = 10
}

variable "primary_data_volume_size" {
  description = "Data volume size for primary PostgreSQL (GB)"
  type        = number
  default     = 50
}

variable "replica_volume_size" {
  description = "Root volume size for replica (GB)"
  type        = number
  default     = 10
}

variable "replica_data_volume_size" {
  description = "Data volume size for replica PostgreSQL (GB)"
  type        = number
  default     = 50
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
}

variable "enable_replica" {
  description = "Enable PostgreSQL replica"
  type        = bool
  default     = true
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "shopper_backend"
}

variable "db_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "r2_endpoint" {
  description = "R2/S3 endpoint for pgbackrest backups"
  type        = string
  default     = "https://paymentform-backups.r2.cloudflarestorage.com"
}

variable "r2_bucket_name" {
  description = "R2/S3 bucket name for pgbackrest backups"
  type        = string
  default     = "paymentform-backups"
}

variable "r2_access_key" {
  description = "R2/S3 access key for pgbackrest"
  type        = string
  sensitive   = true
  default     = ""
}

variable "r2_secret_key" {
  description = "R2/S3 secret key for pgbackrest"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pgbackrest_cipher_pass" {
  description = "Encryption password for pgbackrest"
  type        = string
  sensitive   = true
  default     = ""
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for primary (e.g., us-east-1a)"
  type        = string
  default     = "us-east-1a"
}

variable "replica_availability_zone" {
  description = "Availability zone for replica (e.g., us-east-1b)"
  type        = string
  default     = "us-east-1b"
}

variable "cross_region_availability_zone" {
  description = "Availability zone for cross-region replica (e.g., eu-west-1a)"
  type        = string
  default     = "eu-west-1a"
}

variable "assign_eip" {
  description = "Assign EIP to PostgreSQL primary for stable IP"
  type        = bool
  default     = false
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail logging for audit"
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = "CloudTrail log retention days (365 for SOC2, 90 for PCI)"
  type        = number
  default     = 365
}

variable "enable_backup" {
  description = "Enable automated EBS snapshots"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 30
}

variable "backup_schedule" {
  description = "Cron schedule for backups (default: daily at 2am UTC)"
  type        = string
  default     = "cron(0 2 * ? *)"
}

variable "enable_cross_region_replica" {
  description = "Enable cross-region read replica"
  type        = bool
  default     = false
}

variable "replica_region" {
  description = "AWS region for cross-region replica"
  type        = string
  default     = ""
}

variable "replica_subnet_ids" {
  description = "Subnet IDs for cross-region replica"
  type        = list(string)
  default     = []
}

variable "replica_vpc_id" {
  description = "VPC ID for cross-region replica"
  type        = string
  default     = ""
}

# =============================================================================
# Dynamic Volumes Configuration
# =============================================================================
variable "volumes" {
  description = "List of volumes to create and attach dynamically"
  type = list(object({
    name               = string
    availability_zone  = string
    size               = number
    volume_type        = string
    encrypted          = bool
    iops               = number
    throughput         = number
    device_name        = string
    instance_id        = string
    prevent_destroy    = bool
  }))
  default = []
}

# =============================================================================
# Pre-created Volume IDs (to attach to instances)
# =============================================================================
variable "volume_ids" {
  description = "Map of volume names to volume IDs for attaching to instances"
  type        = map(string)
  default     = {}
}
