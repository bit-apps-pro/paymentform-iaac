output "primary_private_ip" {
  description = "Private IP of the PostgreSQL primary"
  value       = aws_instance.postgresql_primary.private_ip
}

output "primary_public_ip" {
  description = "Public IP of the PostgreSQL primary (if available)"
  value       = aws_instance.postgresql_primary.public_ip
}

output "primary_instance_id" {
  description = "Instance ID of the PostgreSQL primary"
  value       = aws_instance.postgresql_primary.id
}

output "replica_private_ip" {
  description = "Private IP of the PostgreSQL replica"
  value       = var.enable_replica ? aws_instance.postgresql_replica[0].private_ip : null
}

output "replica_instance_id" {
  description = "Instance ID of the PostgreSQL replica"
  value       = var.enable_replica ? aws_instance.postgresql_replica[0].id : null
}

output "connection_string" {
  description = "PostgreSQL connection string"
  sensitive   = true
  value       = "postgresql://${var.db_user}:${var.db_password}@${aws_instance.postgresql_primary.private_ip}:5432/${var.db_name}"
}

output "primary_endpoint" {
  description = "PostgreSQL primary endpoint (IP)"
  value       = var.assign_eip ? aws_eip.primary[0].public_ip : aws_instance.postgresql_primary.public_ip
}

output "replica_endpoint" {
  description = "PostgreSQL replica endpoint (IP)"
  value       = var.enable_replica ? aws_instance.postgresql_replica[0].private_ip : null
}

output "eip_allocation_id" {
  description = "EIP allocation ID for PostgreSQL primary"
  value       = var.assign_eip ? aws_eip.primary[0].id : null
}

output "cross_region_replica_private_ip" {
  description = "Private IP of the cross-region PostgreSQL replica"
  value       = var.enable_cross_region_replica ? aws_instance.postgresql_cross_region_replica[0].private_ip : null
}

output "cross_region_replica_endpoint" {
  description = "Cross-region replica endpoint (private IP)"
  value       = var.enable_cross_region_replica ? aws_instance.postgresql_cross_region_replica[0].private_ip : null
}
