terraform {
  required_providers {
    turso = {
      source  = "celest-dev/turso"
      version = "0.2.3"
    }
  }
}

provider "turso" {
  api_token    = var.turso_api_token
  organization = var.turso_organization
}

# Create Turso organization (if not exists)
# Turso uses organizations for grouping databases

# Create main tenant database
resource "turso_database" "tenant" {
  name  = "${var.resource_prefix}-tenants"
  group = var.turso_group
}

# Create analytics database (for per-tenant analytics)
resource "turso_database" "analytics" {
  name  = "${var.resource_prefix}-analytics"
  group = var.turso_group
}

# Create backup database for disaster recovery
resource "turso_database" "backup" {
  name  = "${var.resource_prefix}-backup"
  group = var.turso_group
}
