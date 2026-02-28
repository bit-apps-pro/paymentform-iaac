# Cloudflare DNS Module Outputs

output "api_dns_record_id" {
  description = "DNS record ID for API subdomain"
  value       = cloudflare_dns_record.api.id
}

output "app_dns_record_id" {
  description = "DNS record ID for App subdomain"
  value       = cloudflare_dns_record.app.id
}

output "renderer_dns_record_id" {
  description = "DNS record ID for renderer wildcard"
  value       = cloudflare_dns_record.renderer_wildcard.id
}

output "api_hostname" {
  description = "Full hostname for API"
  value       = cloudflare_dns_record.api.hostname
}

output "app_hostname" {
  description = "Full hostname for App"
  value       = cloudflare_dns_record.app.hostname
}

output "renderer_hostname" {
  description = "Full hostname pattern for renderer"
  value       = cloudflare_dns_record.renderer_wildcard.hostname
}

output "waf_ruleset_id" {
  description = "WAF ruleset ID (if enabled)"
  value       = try(cloudflare_ruleset.waf_custom[0].id, null)
}

output "rate_limiting_ruleset_id" {
  description = "Rate limiting ruleset ID (if enabled)"
  value       = try(cloudflare_ruleset.rate_limiting[0].id, null)
}

output "cache_ruleset_id" {
  description = "Cache ruleset ID (if enabled)"
  value       = try(cloudflare_ruleset.cache_rules[0].id, null)
}
