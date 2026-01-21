terraform {
  required_providers {
    neon = {
      source  = "kislaya/neon"
      version = "~> 0.3"
    }
  }
}

provider "neon" {
  api_key = var.neon_api_key
}

# Create Neon project
resource "neon_project" "main" {
  name      = "${var.resource_prefix}-${var.environment}"
  region_id = var.neon_region

  tags = merge(
    var.standard_tags,
    { Component = "Database" }
  )
}

# Create database
resource "neon_database" "app" {
  project_id = neon_project.main.id
  name       = replace("${var.resource_prefix}_db", "-", "_")
  owner_name = "postgres"
}

# Create application role
resource "neon_role" "app" {
  project_id = neon_project.main.id
  name       = replace("${var.resource_prefix}_app", "-", "_")
}

# Create read-only role for analytics
resource "neon_role" "readonly" {
  project_id = neon_project.main.id
  name       = replace("${var.resource_prefix}_readonly", "-", "_")
}
