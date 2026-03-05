resource "aws_cloudtrail" "main" {
  name                           = "${var.environment}-cloudtrail"
  s3_bucket_name                 = var.s3_bucket_name
  s3_key_prefix                 = var.s3_key_prefix
  include_global_service_events  = true
  is_multi_region_trail         = var.enable_multi_region
  enable_log_file_validation    = true
  enable_logging               = true
  sns_topic_name               = var.sns_topic_name

  event_selector {
    read_write_type           = "All"
    include_management_events  = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.s3_bucket_name}/*"]
    }
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-cloudtrail"
    }
  )
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.create_s3_bucket ? 1 : 0

  bucket = var.s3_bucket_name

  lifecycle_rule {
    id      = "retention"
    enabled = true

    expiration {
      days = var.retention_days
    }
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "retention"
    enabled = true

    expiration {
      days = var.retention_days
    }
  }

  lifecycle_rule {
    id      = "archive"
    enabled = true
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-cloudtrail-logs"
    }
  )
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  count = var.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.s3_bucket_name}"
      },
      {
        Sid = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
