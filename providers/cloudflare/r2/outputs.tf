# Cloudflare R2 Module Outputs

output "application_storage_bucket_name" {
  description = "Name of the application storage bucket (R2)"
  value       = cloudflare_r2_bucket.application_storage.name
}

output "application_storage_bucket_id" {
  description = "ID of the application storage bucket (R2)"
  value       = cloudflare_r2_bucket.application_storage.id
}

output "public_storage_bucket_name" {
  description = "Name of the public files bucket (R2)"
  value       = var.r2_public_bucket_name != "" ? cloudflare_r2_bucket.public_files[0].name : null
}

output "ssl_config_bucket_name" {
  description = "Name of the SSL config bucket for Caddy certificates"
  value       = var.r2_ssl_bucket_enabled ? cloudflare_r2_bucket.ssl_config[0].name : null
}

output "ssl_config_bucket_id" {
  description = "ID of the SSL config bucket"
  value       = var.r2_ssl_bucket_enabled ? cloudflare_r2_bucket.ssl_config[0].id : null
}

output "r2_endpoint" {
  description = "R2 S3-compatible endpoint URL"
  value       = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}

output "application_storage_bucket_domain" {
  description = "R2 bucket domain for application storage"
  value       = "${cloudflare_r2_bucket.application_storage.name}.r2.cloudflarestorage.com"
}

output "ssl_config_bucket_domain" {
  description = "R2 bucket domain for SSL config bucket"
  value       = var.r2_ssl_bucket_enabled ? "${cloudflare_r2_bucket.ssl_config[0].name}.r2.cloudflarestorage.com" : null
}

output "worker_name" {
  description = "Name of the Cloudflare Worker for public file serving"
  value       = var.worker_enabled && var.worker_route_pattern != "" ? cloudflare_workers_script.cdn_worker[0].script_name : null
}

output "worker_url" {
  description = "URL pattern for accessing files via Worker"
  value       = var.worker_enabled && var.worker_route_pattern != "" ? "https://${replace(var.worker_route_pattern, "/*", "")}" : null
}
