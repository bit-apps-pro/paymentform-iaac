output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.tunnel.token
  sensitive = true
}

output "tunnel_cname" {
  description = "CNAME hostname for the tunnel (use in pg_hba / replica primary_host)"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}.cfargotunnel.com"
}

output "tunnel_hostname" {
  description = "Public hostname for the DB tunnel (e.g. db-tunnel.paymentform.io)"
  value       = local.tunnel_hostname
}

output "service_token_id" {
  description = "Cloudflare Access service token client ID for tunnel clients"
  value       = local.enable_access ? cloudflare_zero_trust_access_service_token.db_tunnel[0].client_id : ""
  sensitive   = true
}

output "service_token_secret" {
  description = "Cloudflare Access service token client secret for tunnel clients"
  value       = local.enable_access ? cloudflare_zero_trust_access_service_token.db_tunnel[0].client_secret : ""
  sensitive   = true
}
