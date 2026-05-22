output "name_suffix" {
  description = "Suffix used on AWS queue names. Consumers MUST set Laravel's SQS_SUFFIX env to this same value so dispatched queue URLs resolve correctly."
  value       = var.name_suffix
}

output "queue_arns" {
  description = "Map of logical queue name to main queue ARN."
  value       = { for q, r in aws_sqs_queue.main : q => r.arn }
}

output "queue_urls" {
  description = "Map of logical queue name to main queue URL."
  value       = { for q, r in aws_sqs_queue.main : q => r.url }
}

output "queue_names" {
  description = "Map of logical queue name to AWS queue name (with prefix)."
  value       = { for q, r in aws_sqs_queue.main : q => r.name }
}

output "dlq_arns" {
  description = "Map of logical queue name to DLQ ARN. Empty when enable_dlq=false."
  value       = { for q, r in aws_sqs_queue.dlq : q => r.arn }
}

output "dlq_urls" {
  description = "Map of logical queue name to DLQ URL. Empty when enable_dlq=false."
  value       = { for q, r in aws_sqs_queue.dlq : q => r.url }
}

output "all_arns" {
  description = "Flat list of every queue ARN (main + DLQ) — convenient for IAM resource bindings."
  value = concat(
    [for r in aws_sqs_queue.main : r.arn],
    [for r in aws_sqs_queue.dlq : r.arn],
  )
}
