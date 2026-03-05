variable "environment" {
  description = "Environment name"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags"
  type        = map(string)
  default     = {}
}

variable "s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  type        = string
}

variable "s3_key_prefix" {
  description = "S3 key prefix for CloudTrail logs"
  type        = string
  default     = "cloudtrail/"
}

variable "enable_multi_region" {
  description = "Enable multi-region trail"
  type        = bool
  default     = true
}

variable "sns_topic_name" {
  description = "SNS topic name for CloudTrail notifications"
  type        = string
  default     = ""
}

variable "create_s3_bucket" {
  description = "Create S3 bucket for CloudTrail logs"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Log retention days (365 for SOC2, 90 for PCI)"
  type        = number
  default     = 365
}
