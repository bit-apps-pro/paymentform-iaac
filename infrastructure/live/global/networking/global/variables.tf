variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Primary domain name for the application"
  type        = string
}

variable "backend_load_balancer_dns" {
  description = "DNS name of the backend load balancer"
  type        = string
}

variable "client_load_balancer_dns" {
  description = "DNS name of the client load balancer"
  type        = string
}

variable "renderer_load_balancer_dns" {
  description = "DNS name of the renderer load balancer"
  type        = string
}

variable "regional_endpoints" {
  description = "Map of regional endpoints for load balancing"
  type = map(object({
    vpc_id       = string
    subnets      = list(string)
    ssl_cert_arn = string
  }))
  default = {}
}