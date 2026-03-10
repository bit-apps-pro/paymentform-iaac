# Cloudflare DNS Module Variables

variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_email" {
  description = "Cloudflare account email"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

# Domain Configuration
variable "domain_name" {
  description = "Root domain name (e.g., paymentform.io)"
  type        = string
}

variable "api_subdomain" {
  description = "API subdomain (e.g., api.sandbox.paymentform.io)"
  type        = string
}

variable "app_subdomain" {
  description = "App subdomain (e.g., app.sandbox.paymentform.io)"
  type        = string
}

variable "renderer_subdomain" {
  description = "Renderer wildcard subdomain (e.g., *.sandbox.paymentform.io)"
  type        = string
}

# Origin Configuration
variable "api_cname" {
  description = "ALB DNS name for API backend (used if not using IP-based origin)"
  type        = string
  default     = ""
}
variable "api_origin_ips" {
  description = "List of origin IPs for API backend"
  type        = list(string)
  default     = []
}

variable "app_origin_ips" {
  description = "List of origin IPs for App frontend"
  type        = list(string)
  default     = []
}

variable "renderer_origin_ip" {
  description = "Origin IP for renderer (fallback if not using containers)"
  type        = string
  default     = ""
}

# Container Endpoints (CNAME targets)
variable "app_container_endpoint" {
  description = "Container endpoint for app (e.g., app-container.containers.cloudflare.com)"
  type        = string
  default     = ""
}

variable "renderer_container_endpoint" {
  description = "Container endpoint for renderer"
  type        = string
  default     = ""
}

# Cloudflare Features
variable "cloudflare_plan" {
  description = "Cloudflare plan type (free, pro, business, enterprise)"
  type        = string
  default     = "free"
}


variable "enable_waf" {
  description = "Enable Web Application Firewall"
  type        = bool
  default     = false
}

variable "enable_rate_limiting" {
  description = "Enable rate limiting"
  type        = bool
  default     = false
}

variable "rate_limit_requests" {
  description = "Number of requests allowed per minute"
  type        = number
  default     = 100
}

variable "health_check_path" {
  description = "Health check path for API"
  type        = string
  default     = "/health"
}

variable "notification_email" {
  description = "Email for Cloudflare notifications"
  type        = string
  default     = ""
}

# Multi-region Geo Routing
variable "enable_geo_routing" {
  description = "Enable geo-routing to multiple regions"
  type        = bool
  default     = false
}

variable "region_endpoints" {
  description = "Map of region names to their endpoints (e.g., { us = \"1.2.3.4\", eu = \"5.6.7.8\", au = \"9.10.11.12\" })"
  type        = map(string)
  default     = {}
}

variable "default_region" {
  description = "Default region to route to if geo lookup fails"
  type        = string
  default     = "us"
}

variable "enable_load_balancer" {
  description = "Enable Cloudflare Load Balancer (requires Pro plan + $5/mo)"
  type        = bool
  default     = false
}

variable "load_balancer_description" {
  description = "Description for the load balancer"
  type        = string
  default     = "Multi-region load balancer"
}

variable "lb_health_check_path" {
  description = "Health check path for load balancer pools"
  type        = string
  default     = "/health"
}

variable "lb_health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "lb_health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "lb_account_id" {
  description = "Cloudflare account ID for load balancer"
  type        = string
  default     = ""
}
