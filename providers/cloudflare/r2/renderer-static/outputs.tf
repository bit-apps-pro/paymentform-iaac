output "bucket_name" {
  description = "Fully-qualified R2 bucket name (with environment prefix). Pass to CI for rclone target."
  value       = cloudflare_r2_bucket.renderer_static.name
}

output "bucket_id" {
  description = "R2 bucket resource ID."
  value       = cloudflare_r2_bucket.renderer_static.id
}

output "custom_domain_url" {
  description = "Public HTTPS URL for the bucket — consumed by the renderer as `NEXT_PUBLIC_CDN_URL` at build time."
  value       = "https://${cloudflare_r2_custom_domain.renderer_static.domain}"
}

output "custom_domain" {
  description = "Bare hostname of the R2 custom domain."
  value       = cloudflare_r2_custom_domain.renderer_static.domain
}
