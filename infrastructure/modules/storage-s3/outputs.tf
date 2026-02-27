output "application_storage_bucket_name" {
  description = "Name of the application storage bucket"
  value       = aws_s3_bucket.application_storage.bucket
}

output "application_storage_bucket_arn" {
  description = "ARN of the application storage bucket"
  value       = aws_s3_bucket.application_storage.arn
}

output "logs_bucket_name" {
  description = "Name of the logs bucket"
  value       = aws_s3_bucket.logs.bucket
}

output "logs_bucket_arn" {
  description = "ARN of the logs bucket"
  value       = aws_s3_bucket.logs.arn
}

output "static_assets_bucket_name" {
  description = "Name of the static assets bucket"
  value       = aws_s3_bucket.static_assets.bucket
}

output "static_assets_bucket_arn" {
  description = "ARN of the static assets bucket"
  value       = aws_s3_bucket.static_assets.arn
}

output "static_assets_cloudfront_domain" {
  description = "Domain name of the CloudFront distribution for static assets"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.static_assets_cf[0].domain_name : null
}

output "static_assets_cloudfront_arn" {
  description = "ARN of the CloudFront distribution for static assets"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.static_assets_cf[0].arn : null
}