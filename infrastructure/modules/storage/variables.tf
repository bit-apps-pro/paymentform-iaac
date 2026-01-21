variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for static assets"
  type        = bool
  default     = false
}

variable "lifecycle_transition_days" {
  description = "Number of days after which to transition objects to STANDARD_IA"
  type        = number
  default     = 30
}

variable "lifecycle_archive_days" {
  description = "Number of days after which to archive objects to GLACIER"
  type        = number
  default     = 60
}

variable "lifecycle_expiration_days" {
  description = "Number of days after which to expire object versions"
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the logs bucket"
  type        = number
  default     = 30
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}