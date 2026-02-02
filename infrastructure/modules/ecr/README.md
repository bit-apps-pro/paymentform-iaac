ECR module (cost-optimized)

This module creates one ECR repository per service name supplied, with aggressive lifecycle policies to minimize storage costs.

Key cost-optimization defaults:
- Keep only the last 3 tagged images per repository (configurable)
- Expire untagged images older than 1 day (configurable)
- Single-region deployment, no replication
- Image scanning on push enabled
- AES256 encryption at rest
- Immutable tags are enabled automatically for the "prod" environment

Estimated cost:
- ECR storage cost is roughly $0.10/GB-month (varies by region). With lifecycle rules keeping ~3 images per service and small image sizes, expected monthly cost is approximately $1-5 for all four services combined.

Usage:
module "ecr" {
  source = "./modules/ecr"
  environment = var.environment
  repositories = var.ecr_repositories
  name_prefix = local.resource_prefix
  standard_tags = local.standard_tags
}
