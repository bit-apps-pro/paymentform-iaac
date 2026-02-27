output "application_storage_bucket_name" {
  description = "Name of the application storage bucket (R2)"
  value       = cloudflare_r2_bucket.application_storage.name
}

output "application_storage_bucket_arn" {
  description = "ARN/ID of the application storage bucket (R2)"
  value       = cloudflare_r2_bucket.application_storage.id
}

output "worker_name" {
  description = "Name of the Cloudflare Worker for public file serving"
  value       = var.worker_enabled && var.worker_route_pattern != "" ? cloudflare_workers_script.cdn_worker[0].script_name : null
}

output "worker_url" {
  description = "URL pattern for accessing files via Worker"
  value       = var.worker_enabled && var.worker_route_pattern != "" ? "https://${replace(var.worker_route_pattern, "/*", "")}" : null
}

output "r2_endpoint" {
  description = "R2 S3-compatible endpoint URL"
  value       = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}

output "r2_bucket_domain" {
  description = "R2 bucket domain for direct access (private)"
  value       = "${cloudflare_r2_bucket.application_storage.name}.r2.cloudflarestorage.com"
}
