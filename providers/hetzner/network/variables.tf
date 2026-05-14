variable "enabled" {
  description = "Whether to create the Hetzner network resources"
  type        = bool
  default     = true
}

variable "environment" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "network_zone" {
  description = "Hetzner network zone (eu-central, ap-southeast, us-east, us-west)"
  type        = string
}

variable "ip_range" {
  description = "CIDR for the entire network (e.g. 10.10.0.0/16)"
  type        = string
}

variable "subnet_ip_range" {
  description = "CIDR for the subnet, must be within ip_range (e.g. 10.10.1.0/24)"
  type        = string
}

variable "standard_tags" {
  type    = map(string)
  default = {}
}
