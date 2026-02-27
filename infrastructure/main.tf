# Infrastructure module main configuration
# This file sources all infrastructure modules

# Networking module
module "networking" {
  source = "./modules/networking"

  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  standard_tags       = local.standard_tags
}

# Security module
# Manages VPC security groups for EC2 instances
# Traefik runs on EC2 and handles SSL/TLS (Cloudflare provides DNS)
module "security" {
  source = "./modules/security"

  environment            = var.environment
  vpc_id                 = module.networking.vpc_id
  app_ports              = var.app_ports
  enable_strict_security = var.enable_strict_security
  standard_tags          = local.standard_tags
}

# Storage module (Cloudflare R2)
module "storage" {
  source = "./modules/storage"

  environment           = var.environment
  standard_tags         = local.standard_tags
  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id
  r2_bucket_name        = var.r2_bucket_name
  r2_public_bucket_name = var.r2_public_bucket_name
  worker_enabled        = var.worker_enabled
  worker_route_pattern  = var.worker_route_pattern
  log_retention_days    = var.log_retention_days
  cors_allowed_origins  = var.cors_allowed_origins
}

# Compute module
# Backend compute module (Laravel/FrankenPHP + Caddy — ports 80/443)
# In public subnets so Cloudflare can proxy directly to it (no ALB needed for sandbox)
module "compute_backend" {
  source = "./modules/compute"

  environment                = var.environment
  instance_prefix            = "${var.environment}-backend"
  subnet_ids                 = module.networking.public_subnet_ids
  instance_type              = var.backend_instance_type
  ami_id                     = var.backend_ami_id != "" ? var.backend_ami_id : var.ami_id
  key_pair_name              = var.key_pair_name
  min_size                   = 1
  max_size                   = 2
  desired_capacity           = var.backend_desired_capacity
  scaling_cpu_threshold      = var.scaling_cpu_threshold
  scaling_down_cpu_threshold = var.scaling_down_cpu_threshold
  standard_tags              = local.standard_tags
  detailed_monitoring        = var.detailed_monitoring
  ebs_optimized              = var.ebs_optimized
  root_volume_size           = var.root_volume_size
  root_volume_type           = var.root_volume_type
  ecs_cluster_name           = "${var.ecs_cluster_name}-backend"
  ecs_security_group_id      = module.security.ecs_security_group_id
  region                     = var.region
  bucket_name                = module.storage.application_storage_bucket_name
  service_type               = "backend"
}

# Renderer compute module (Next.js + Caddy — port 443, on-demand TLS for wildcard subdomains)
# Must be in public subnets: Cloudflare DNS-only, so Caddy receives direct TLS connections
module "compute_renderer" {
  source = "./modules/compute"

  environment                = var.environment
  instance_prefix            = "${var.environment}-renderer"
  subnet_ids                 = module.networking.public_subnet_ids
  instance_type              = var.renderer_instance_type
  ami_id                     = var.renderer_ami_id != "" ? var.renderer_ami_id : var.ami_id
  key_pair_name              = var.key_pair_name
  min_size                   = 1
  max_size                   = 2
  desired_capacity           = var.renderer_desired_capacity
  scaling_cpu_threshold      = var.scaling_cpu_threshold
  scaling_down_cpu_threshold = var.scaling_down_cpu_threshold
  standard_tags              = local.standard_tags
  detailed_monitoring        = var.detailed_monitoring
  ebs_optimized              = var.ebs_optimized
  root_volume_size           = var.root_volume_size
  root_volume_type           = var.root_volume_type
  ecs_cluster_name           = "${var.ecs_cluster_name}-renderer"
  ecs_security_group_id      = module.security.ecs_security_group_id
  region                     = var.region
  bucket_name                = module.storage.application_storage_bucket_name
  service_type               = "renderer"
}

# SSM module to provision application secrets as SecureString parameters
module "ssm" {
  source = "./modules/ssm"

  environment       = var.environment
  app_key           = var.app_key
  redis_password    = var.redis_password
  turso_auth_token  = var.turso_auth_token
  turso_api_token   = var.turso_api_token
  neon_database_url = var.neon_database_url
  kms_key_id        = var.kms_key_id

  db_password                   = var.db_password
  pgadmin_default_password      = var.pgadmin_default_password
  tenant_db_auth_token          = var.tenant_db_auth_token
  tenant_db_encryption_key      = var.tenant_db_encryption_key
  mail_password                 = var.mail_password
  aws_access_key_id             = var.aws_access_key_id
  aws_secret_access_key         = var.aws_secret_access_key
  google_client_secret          = var.google_client_secret
  stripe_secret                 = var.stripe_secret
  stripe_client_id              = var.stripe_client_id
  stripe_connect_webhook_secret = var.stripe_connect_webhook_secret
  kv_store_api_token            = var.kv_store_api_token
  ghcr_token                    = var.ghcr_token
}

# Cloudflare DNS module
# Backend: Cloudflare proxied → EC2 backend (ports 80/443, Caddy/FrankenPHP)
# Renderer: Cloudflare DNS-only → EC2 renderer (port 443, Caddy on-demand TLS)
module "cloudflare" {
  source = "./modules/cloudflare"

  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_plan       = var.cloudflare_plan
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_account_id = var.cloudflare_account_id
  environment           = var.environment
  api_subdomain         = var.api_subdomain
  app_subdomain         = var.app_subdomain
  renderer_subdomain    = var.renderer_subdomain
  renderer_origin_ip    = length(module.compute_renderer.instance_ips) > 0 ? module.compute_renderer.instance_ips[0] : var.renderer_origin_ip
  enable_load_balancer  = var.enable_cloudflare_lb
  api_origin_ips        = module.compute_backend.instance_ips
  app_origin_ips        = module.compute_backend.instance_ips
  health_check_path     = var.health_check_path
  notification_email    = var.notification_email
  enable_waf            = var.enable_cloudflare_waf
  enable_rate_limiting  = var.enable_rate_limiting
  rate_limit_requests   = var.rate_limit_requests
  standard_tags         = local.standard_tags
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
