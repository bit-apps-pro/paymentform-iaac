# Infrastructure module main configuration
# This file sources all infrastructure modules

# Networking module
module "networking" {
  source = "./modules/networking"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  standard_tags        = local.standard_tags
}

# Security module
module "security" {
  source = "./modules/security"

  environment             = var.environment
  vpc_id                  = module.networking.vpc_id
  app_ports               = var.app_ports
  neon_api_key_secret_arn = var.neon_api_key_secret_arn
  turso_token_secret_arn  = var.turso_token_secret_arn
  enable_strict_security  = var.enable_strict_security
  standard_tags           = local.standard_tags
}

# ALB module
module "alb" {
  source = "./modules/alb"

  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  public_subnet_ids          = module.networking.public_subnet_ids
  alb_security_group_id      = module.security.alb_security_group_id
  ssl_certificate_arn        = var.ssl_certificate_arn
  enable_deletion_protection = var.enable_deletion_protection
  standard_tags              = local.standard_tags
  enable_access_logs         = var.enable_alb_access_logs
}

# Storage module
module "storage" {
  source = "./modules/storage"

  environment          = var.environment
  standard_tags        = local.standard_tags
  enable_versioning    = var.enable_versioning
  enable_cloudfront    = var.enable_cloudfront
  log_retention_days   = var.log_retention_days
  cors_allowed_origins = var.cors_allowed_origins
}

# Compute module
module "compute" {
  source = "./modules/compute"

  environment                = var.environment
  subnet_ids                 = module.networking.private_subnet_ids
  instance_type              = var.instance_type
  ami_id                     = var.ami_id
  key_pair_name              = var.key_pair_name
  min_size                   = var.min_size
  max_size                   = var.max_size
  desired_capacity           = var.desired_capacity
  scaling_cpu_threshold      = var.scaling_cpu_threshold
  scaling_down_cpu_threshold = var.scaling_down_cpu_threshold
  standard_tags              = local.standard_tags
  detailed_monitoring        = var.detailed_monitoring
  ebs_optimized              = var.ebs_optimized
  root_volume_size           = var.root_volume_size
  root_volume_type           = var.root_volume_type
  ecs_cluster_name           = var.ecs_cluster_name
  ecs_security_group_id      = module.security.ecs_security_group_id
}

# Neon database module
module "neon_database" {
  source = "./modules/neon"

  neon_api_key    = var.neon_api_key
  neon_region     = var.neon_region_map[var.region]
  resource_prefix = local.resource_prefix
  environment     = var.environment
  standard_tags   = local.standard_tags
}

# Turso database module
module "turso_database" {
  source = "./modules/turso"

  turso_api_token    = var.turso_api_token
  turso_organization = var.turso_organization
  turso_group        = var.turso_group
  resource_prefix    = local.resource_prefix
  environment        = var.environment
  standard_tags      = local.standard_tags
}

# Cloudflare DNS and Load Balancing module
module "cloudflare" {
  source = "./modules/cloudflare"

  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_account_id = var.cloudflare_account_id
  environment           = var.environment
  api_subdomain         = var.api_subdomain
  app_subdomain         = var.app_subdomain
  renderer_subdomain    = var.renderer_subdomain
  renderer_origin_ip    = var.renderer_origin_ip
  enable_load_balancer  = var.enable_cloudflare_lb
  api_origin_ips        = module.alb.alb_dns_name != "" ? [module.alb.alb_dns_name] : []
  app_origin_ips        = module.alb.alb_dns_name != "" ? [module.alb.alb_dns_name] : []
  health_check_path     = var.health_check_path
  notification_email    = var.notification_email
  enable_waf            = var.enable_cloudflare_waf
  enable_rate_limiting  = var.enable_rate_limiting
  rate_limit_requests   = var.rate_limit_requests
  standard_tags         = local.standard_tags
}

# Optional ECR module for sandbox and prod environments
module "ecr" {
  source = "./modules/ecr"
  count  = var.enable_ecr && contains(["sandbox", "prod"], var.environment) ? 1 : 0

  environment   = var.environment
  repositories  = var.ecr_repositories
  name_prefix   = local.resource_prefix
  standard_tags = local.standard_tags
}

# Attach ECR pull policy to compute instance role when ECR is enabled
resource "aws_iam_role_policy_attachment" "compute_instance_ecr_pull" {
  count      = var.enable_ecr && contains(["sandbox", "prod"], var.environment) ? 1 : 0
  role       = module.compute.instance_role_name
  policy_arn = module.ecr[0].ecr_pull_policy_arn
  depends_on = [module.ecr, module.compute]
}

# AWS Amplify module for renderer and client deployments
module "amplify" {
  source = "./modules/amplify"
  count  = var.enable_amplify ? 1 : 0

  resource_prefix             = local.resource_prefix
  environment                 = var.environment
  standard_tags               = local.standard_tags
  renderer_repository_url     = var.renderer_repository_url
  renderer_branch_name        = var.renderer_branch_name
  renderer_env_vars           = var.renderer_env_vars
  renderer_custom_domain      = var.renderer_custom_domain
  renderer_subdomain_prefix   = var.renderer_subdomain_prefix
  client_repository_url       = var.client_repository_url
  client_branch_name          = var.client_branch_name
  client_env_vars             = var.client_env_vars
  client_custom_domain        = var.client_custom_domain
  client_subdomain_prefix     = var.client_subdomain_prefix
  access_token                = var.amplify_access_token
  enable_auto_branch_creation = false
  enable_branch_auto_build    = true
  enable_branch_auto_deletion = false
}
