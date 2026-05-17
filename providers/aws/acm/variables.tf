variable "domain_name" {
  description = "Primary domain name for the certificate (e.g., api.paymentform.io)"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional SANs for the certificate"
  type        = list(string)
  default     = []
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID where DNS validation records will be created"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to the certificate"
  type        = map(string)
  default     = {}
}
