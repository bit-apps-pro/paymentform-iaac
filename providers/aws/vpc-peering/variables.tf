variable "requester_vpc_id" {
  description = "ID of the requester VPC (local region)"
  type        = string
}

variable "requester_route_table_id" {
  description = "ID of the requester VPC's public route table"
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR block of the requester VPC"
  type        = string
}

variable "peer_vpc_id" {
  description = "ID of the peer VPC (remote region)"
  type        = string
}

variable "peer_route_table_id" {
  description = "ID of the peer VPC's public route table"
  type        = string
}

variable "peer_vpc_cidr" {
  description = "CIDR block of the peer VPC"
  type        = string
}

variable "peer_region" {
  description = "AWS region of the peer VPC"
  type        = string
}

variable "peer_owner_id" {
  description = "AWS account ID of peer VPC owner (empty = same account)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to resources"
  type        = map(string)
  default     = {}
}
