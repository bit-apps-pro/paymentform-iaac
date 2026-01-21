terraform {
  required_providers {
    turso = {
      source  = "tursodatabase/turso"
      version = "~> 0.1"
    }
  }
}

provider "turso" {
  api_token = var.turso_api_token
}

# Create Turso organization (if not exists)
# Turso uses organizations for grouping databases

# Create main tenant database
resource "turso_database" "tenant" {
  name       = "${var.resource_prefix}-tenants"
  group      = var.turso_group
  is_clone   = false
  is_replica = false

  tags = merge(
    var.standard_tags,
    { Component = "TenantDatabase" }
  )
}

# Create analytics database (for per-tenant analytics)
resource "turso_database" "analytics" {
  name       = "${var.resource_prefix}-analytics"
  group      = var.turso_group
  is_clone   = false
  is_replica = false

  tags = merge(
    var.standard_tags,
    { Component = "AnalyticsDatabase" }
  )
}

# Create backup database for disaster recovery
resource "turso_database" "backup" {
  name       = "${var.resource_prefix}-backup"
  group      = var.turso_group
  is_clone   = false
  is_replica = false

  tags = merge(
    var.standard_tags,
    { Component = "BackupDatabase" }
  )
}
