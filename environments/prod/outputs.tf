
output "region" {
  value = local.region
}

output "alb_backend_dns_name" {
  description = "DNS name of the backend ALB (api.paymentform.io target)"
  value       = module.paymentform_alb_backend.alb_dns_name
}

output "nlb_renderer_dns_name" {
  description = "DNS name of the renderer NLB (*.paymentform.io target)"
  value       = module.paymentform_nlb_renderer.nlb_dns_name
}

output "instance_ips" {
  value = module.paymentform_backend.instance_ips
}

output "instance_ids" {
  description = "Map of backend instance IDs (backend_1:i-xxx, backend_2:i-xxx)"
  value       = { for idx, id in module.paymentform_backend.instance_ids : "backend_${idx + 1}" => id }
}

output "renderer_instance_ids" {
  description = "Map of renderer instance IDs (renderer_1:i-xxx, renderer_2:i-xxx)"
  value       = { for idx, id in module.paymentform_renderer.instance_ids : "renderer_${idx + 1}" => id }
}

output "database_instance_ids" {
  description = "Map of database instance IDs"
  value = {
    primary              = module.postgres_database.primary_instance_id
    replica              = module.postgres_database.replica_instance_id
    cross_region_replica = module.postgres_database.cross_region_replica_instance_id
  }
}

output "valkey_instance_ids" {
  description = "Map of Valkey instance IDs (valkey_1:i-xxx, valkey_2:i-xxx)"
  value       = { for idx, id in module.paymentform_cache.instance_ids : "valkey_${idx + 1}" => id }
}

output "database_primary_endpoint" {
  value = module.postgres_database.primary_endpoint
}

output "database_replica_endpoint" {
  value = module.postgres_database.replica_endpoint
}

output "valkey_primary_endpoint" {
  value = module.paymentform_cache.primary_endpoint
}

output "postgresql_primary_data_volume_id" {
  description = "Volume ID for PostgreSQL primary data"
  value       = module.postgres_primary_volume.volume_id
}

output "postgresql_replica_data_volume_id" {
  description = "Volume ID for PostgreSQL replica data"
  value       = module.postgres_replica_volume.volume_id
}

output "kv_store_namespace_id" {
  description = "Namespace id for kv store"
  value       = module.paymentform_kv_store.namespace_id
}

output "kv_store_endpoint" {
  description = "KV store worker endpoint URL"
  value       = module.paymentform_kv_store.kv_store_endpoint
}

output "tunnel_token" {
  description = "Cloudflare tunnel token for the DB tunnel"
  value       = module.tunnel_db.tunnel_token
  sensitive   = true
}

output "tunnel_hostname" {
  description = "Public hostname for the DB tunnel"
  value       = module.tunnel_db.tunnel_hostname
}

output "service_token_id" {
  description = "Cloudflare Access service token client ID"
  value       = module.tunnel_db.service_token_id
  sensitive   = true
}

output "service_token_secret" {
  description = "Cloudflare Access service token client secret"
  value       = module.tunnel_db.service_token_secret
  sensitive   = true
}
