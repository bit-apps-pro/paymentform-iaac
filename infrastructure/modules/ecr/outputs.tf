output "repository_urls" {
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
  description = "Map of repository names to their URLs"
}

output "repository_arns" {
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
  description = "Map of repository names to their ARNs"
}

output "ecr_pull_policy_arn" {
  value       = aws_iam_policy.ecr_pull.arn
  description = "ARN of the IAM policy allowing read-only pulls from these repositories"
}
