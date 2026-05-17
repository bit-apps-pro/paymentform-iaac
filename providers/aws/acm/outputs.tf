output "certificate_arn" {
  description = "ARN of the validated ACM certificate (use this in ALB/CloudFront listener)"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "Primary domain name"
  value       = aws_acm_certificate.this.domain_name
}
