# Turso multi-region database configuration
# Note: Turso is a separate service from AWS, so this would be configured separately
# This file documents the intended setup and provides automation scripts

variable "turso_organization" {
  description = "Turso organization name"
  type        = string
}

variable "turso_token" {
  description = "Turso API token"
  type        = string
  sensitive   = true
}

variable "turso_primary_location" {
  description = "Primary location for Turso database"
  type        = string
  default     = "us-east"
}

variable "turso_replica_locations" {
  description = "Replica locations for Turso database"
  type        = list(string)
  default     = ["eu-west", "ap-south"]
}

variable "database_name" {
  description = "Name of the Turso database"
  type        = string
  default     = "tenant-db"
}

# This would be implemented as a script or using Turso's CLI in a real deployment
# resource "null_resource" "turso_setup" {
#   triggers = {
#     turso_token = var.turso_token
#   }
#
#   provisioner "local-exec" {
#     command = <<EOT
#       #!/bin/bash
#       export TURSO_API_TOKEN="${var.turso_token}"
#       
#       # Create the database in primary location
#       turso db create ${var.database_name} --location ${var.turso_primary_location}
#       
#       # Create replicas in specified locations
#       for location in ${join(" ", var.turso_replica_locations)}; do
#         turso db replicate ${var.database_name} --from-location ${var.turso_primary_location} --to-location $location
#       done
#     EOT
#   }
# }

# Outputs for Turso configuration
output "primary_database_url" {
  description = "URL for the primary Turso database"
  value       = "libsql://${var.database_name}.${var.turso_primary_location}.turso.io"
}

output "replica_urls" {
  description = "URLs for the Turso database replicas"
  value = [
    for location in var.turso_replica_locations :
    "libsql://${var.database_name}.${location}.turso.io"
  ]
}

output "database_name" {
  description = "Name of the Turso database"
  value       = var.database_name
}