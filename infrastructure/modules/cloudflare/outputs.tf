# Cloudflare Module Outputs

output "api_record_id" {
  description = "Cloudflare DNS record ID for API"
  value       = cloudflare_dns_record.api.id
}

output "app_record_id" {
  description = "Cloudflare DNS record ID for App"
  value       = cloudflare_dns_record.app.id
}

output "renderer_record_id" {
  description = "Cloudflare DNS record ID for Renderer wildcard"
  value       = cloudflare_dns_record.renderer_wildcard.id
}

output "waf_ruleset_id" {
  description = "WAF ruleset ID"
  value       = var.enable_waf ? cloudflare_ruleset.waf_custom[0].id : null
}

output "rate_limiting_ruleset_id" {
  description = "Rate limiting ruleset ID"
  value       = (var.cloudflare_plan == "business" || var.cloudflare_plan == "enterprise") && var.enable_rate_limiting ? cloudflare_ruleset.rate_limiting[0].id : null
}

output "tenants_kv_namespace_id" {
  description = "Cloudflare KV namespace ID for tenant storage"
  value       = var.environment != "dev" ? cloudflare_workers_kv_namespace.tenants[0].id : "local-dev-namespace"
}

output "tenants_kv_namespace_title" {
  description = "Cloudflare KV namespace title"
  value       = var.environment != "dev" ? cloudflare_workers_kv_namespace.tenants[0].title : "local-dev-namespace"
}
