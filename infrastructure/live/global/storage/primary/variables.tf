variable "aws_region" {
  description = "AWS region for the primary storage"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "primary_bucket_name" {
  description = "Name of the primary S3 bucket"
  type        = string
}

variable "replica_regions" {
  description = "List of regions for S3 bucket replicas"
  type        = list(string)
  default     = ["eu-west-1", "ap-southeast-1"]
}