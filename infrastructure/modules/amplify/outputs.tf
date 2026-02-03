# AWS Amplify module outputs

# Renderer outputs
output "renderer_app_id" {
  description = "Amplify app ID for renderer"
  value       = aws_amplify_app.renderer.id
}

output "renderer_app_arn" {
  description = "Amplify app ARN for renderer"
  value       = aws_amplify_app.renderer.arn
}

output "renderer_default_domain" {
  description = "Default Amplify domain for renderer"
  value       = aws_amplify_app.renderer.default_domain
}

output "renderer_branch_url" {
  description = "URL for renderer branch"
  value       = "https://${aws_amplify_branch.renderer_main.branch_name}.${aws_amplify_app.renderer.default_domain}"
}

output "renderer_custom_domain_url" {
  description = "Custom domain URL for renderer (if configured)"
  value       = var.renderer_custom_domain != "" ? "https://${var.renderer_subdomain_prefix != "" ? "${var.renderer_subdomain_prefix}." : ""}${var.renderer_custom_domain}" : ""
}

# Client outputs
output "client_app_id" {
  description = "Amplify app ID for client"
  value       = aws_amplify_app.client.id
}

output "client_app_arn" {
  description = "Amplify app ARN for client"
  value       = aws_amplify_app.client.arn
}

output "client_default_domain" {
  description = "Default Amplify domain for client"
  value       = aws_amplify_app.client.default_domain
}

output "client_branch_url" {
  description = "URL for client branch"
  value       = "https://${aws_amplify_branch.client_main.branch_name}.${aws_amplify_app.client.default_domain}"
}

output "client_custom_domain_url" {
  description = "Custom domain URL for client (if configured)"
  value       = var.client_custom_domain != "" ? "https://${var.client_subdomain_prefix != "" ? "${var.client_subdomain_prefix}." : ""}${var.client_custom_domain}" : ""
}
