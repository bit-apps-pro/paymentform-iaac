
output "region" {
  value = local.region
}

output "alb_dns_name" {
  value = module.paymentform_alb.alb_dns_name
}

output "alb_zone_id" {
  value = module.paymentform_alb.alb_zone_id
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

output "paymentform_kv_store_namespace_id" {
  description = "Namespace id for kv store"
  value       = module.paymentform_kv_store.namespace_id
}
