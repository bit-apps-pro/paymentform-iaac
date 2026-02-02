# Cloudflare Module Outputs

output "api_record_id" {
  description = "Cloudflare DNS record ID for API"
  value       = cloudflare_record.api.id
}

output "app_record_id" {
  description = "Cloudflare DNS record ID for App"
  value       = cloudflare_record.app.id
}

output "renderer_record_id" {
  description = "Cloudflare DNS record ID for Renderer wildcard"
  value       = cloudflare_record.renderer_wildcard.id
}

output "api_lb_id" {
  description = "Cloudflare Load Balancer ID for API"
  value       = var.enable_load_balancer ? cloudflare_load_balancer.api_lb[0].id : null
}

output "app_lb_id" {
  description = "Cloudflare Load Balancer ID for App"
  value       = var.enable_load_balancer ? cloudflare_load_balancer.app_lb[0].id : null
}

output "api_pool_id" {
  description = "Cloudflare origin pool ID for API"
  value       = var.enable_load_balancer ? cloudflare_load_balancer_pool.api_pool[0].id : null
}

output "app_pool_id" {
  description = "Cloudflare origin pool ID for App"
  value       = var.enable_load_balancer ? cloudflare_load_balancer_pool.app_pool[0].id : null
}

output "waf_ruleset_id" {
  description = "WAF ruleset ID"
  value       = var.enable_waf ? cloudflare_ruleset.waf_managed[0].id : null
}

output "rate_limiting_ruleset_id" {
  description = "Rate limiting ruleset ID"
  value       = var.enable_rate_limiting ? cloudflare_ruleset.rate_limiting[0].id : null
}
