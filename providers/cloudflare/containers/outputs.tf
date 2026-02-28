# Cloudflare Container Module Outputs

output "container_id" {
  description = "Container ID"
  value       = try(cloudflare_container.this[0].id, null)
}

output "container_name" {
  description = "Container name"
  value       = local.full_container_name
}

output "container_endpoint" {
  description = "Container endpoint URL"
  value       = var.container_enabled ? "${local.full_container_name}.containers.cloudflare.com" : null
}

output "dns_record_id" {
  description = "DNS record ID"
  value       = try(cloudflare_dns_record.this[0].id, null)
}

output "dns_record_name" {
  description = "DNS record name (domain)"
  value       = var.domain_name
}

output "registry_credential_id" {
  description = "Registry credential ID"
  value       = try(cloudflare_registry_credential.this[0].id, null)
}
