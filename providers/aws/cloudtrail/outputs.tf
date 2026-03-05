output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  value       = var.create_s3_bucket ? aws_s3_bucket.cloudtrail_logs[0].id : var.s3_bucket_name
}
