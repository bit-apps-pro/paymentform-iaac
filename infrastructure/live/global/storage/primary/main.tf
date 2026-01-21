terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-storage-primary-state"
    key            = "storage/primary/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "paymentform-terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "paymentform"
      Environment = var.environment
      Component   = "storage-primary"
      ManagedBy   = "terraform"
    }
  }
}

# Primary S3 bucket
module "primary_storage" {
  source = "../../modules/s3-bucket"

  bucket_name            = var.primary_bucket_name
  region                 = var.aws_region
  environment            = var.environment
  enable_versioning      = true
  enable_encryption      = true
  block_public_access    = true
  lifecycle_rule_enabled = true
}

# Cross-region replication setup
resource "aws_s3_bucket" "replica" {
  for_each = toset(var.replica_regions)

  bucket = "${var.primary_bucket_name}-${each.value}"

  tags = {
    Name              = "${var.primary_bucket_name}-${each.value}"
    Environment       = var.environment
    ReplicationTarget = "true"
  }
}

# IAM role for replication
resource "aws_iam_role" "s3_replication" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for replication
resource "aws_iam_policy" "s3_replication" {
  name = "s3-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          "${module.primary_storage.bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetReplicationConfiguration"
        ]
        Resource = [
          module.primary_storage.bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = [
          for region in var.replica_regions :
          "arn:aws:s3:::${var.primary_bucket_name}-${region}/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "s3_replication" {
  role       = aws_iam_role.s3_replication.name
  policy_arn = aws_iam_policy.s3_replication.arn
}

# Enable cross-region replication on primary bucket
resource "aws_s3_bucket_replication_configuration" "primary" {
  bucket = module.primary_storage.bucket_id

  role = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-to-all-regions"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replica[var.replica_regions[0]].arn
      storage_class = "STANDARD"
    }
  }

  # Add additional rules for other regions if needed
  dynamic "rule" {
    for_each = slice(var.replica_regions, 1, length(var.replica_regions))
    content {
      id     = "replicate-to-${rule.value}"
      status = "Enabled"

      destination {
        bucket        = aws_s3_bucket.replica[rule.value].arn
        storage_class = "STANDARD"
      }
    }
  }
}

# Bucket policies for replica buckets
resource "aws_s3_bucket_policy" "replica" {
  for_each = aws_s3_bucket.replica

  bucket = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSSLRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          each.value.arn,
          "${each.value.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Outputs
output "primary_bucket_id" {
  description = "ID of the primary S3 bucket"
  value       = module.primary_storage.bucket_id
}

output "primary_bucket_arn" {
  description = "ARN of the primary S3 bucket"
  value       = module.primary_storage.bucket_arn
}

output "replica_bucket_ids" {
  description = "IDs of the replica S3 buckets"
  value = {
    for region, bucket in aws_s3_bucket.replica :
    region => bucket.id
  }
}

output "replica_bucket_arns" {
  description = "ARNs of the replica S3 buckets"
  value = {
    for region, bucket in aws_s3_bucket.replica :
    region => bucket.arn
  }
}