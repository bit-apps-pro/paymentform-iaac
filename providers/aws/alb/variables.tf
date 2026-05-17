variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix (e.g., paymentform-prod-backend)"
  type        = string
}

variable "service_label" {
  description = "Short service label for resource names (e.g., bknd)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs (≥2 in different AZs) for the ALB"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN to attach to the HTTPS listener"
  type        = string
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds (3600 to keep Reverb WebSocket connections alive)"
  type        = number
  default     = 3600
}

variable "stickiness_cookie_duration" {
  description = "Sticky session cookie duration in seconds (for WS connection persistence)"
  type        = number
  default     = 86400
}

variable "enable_deletion_protection" {
  description = "Whether to enable ALB deletion protection"
  type        = bool
  default     = false
}

variable "standard_tags" {
  description = "Standard tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "alert_webhook_url" {
  description = "Webhook URL for unhealthy-host alerts (optional, only used if SNS+Lambda pattern is wired)"
  type        = string
  default     = ""
}

variable "alert_sustained_minutes" {
  description = "Minutes a host must be unhealthy before alerting"
  type        = number
  default     = 5
}
