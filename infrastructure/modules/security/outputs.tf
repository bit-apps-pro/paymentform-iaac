output "ecs_security_group_id" {
  description = "ID of the EC2/Traefik security group"
  value       = aws_security_group.ecs.id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.name
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.ecs_task_role.name
}

output "secrets_manager_access_policy_arn" {
  description = "ARN of the secrets manager access policy"
  value       = aws_iam_policy.secrets_manager_access.arn
}

output "cloudwatch_logs_access_policy_arn" {
  description = "ARN of the CloudWatch logs access policy"
  value       = aws_iam_policy.cloudwatch_logs_access.arn
}

output "encryption_key_arn" {
  description = "ARN of the KMS encryption key"
  value       = aws_kms_key.encryption_key.arn
}

output "encryption_key_alias" {
  description = "Alias of the KMS encryption key"
  value       = aws_kms_alias.encryption_key_alias.name
}

output "ec2_cloudflare_security_group_id" {
  description = "ID of the EC2 security group for Cloudflare-only access"
  value       = var.use_cloudflare ? aws_security_group.ec2_cloudflare[0].id : null
}
