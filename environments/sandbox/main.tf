# Sandbox Environment Configuration
# Calls provider modules directly

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-terraform-state"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "paymentform-terraform-locks"
  }
}

locals {
  resource_prefix = "paymentform-sandbox"

  standard_tags = {
    Environment = "sandbox"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }
}

# ============================================================================
# AWS Infrastructure
# ============================================================================

module "aws_networking" {
  source = "../../providers/aws/networking"

  environment         = "sandbox"
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  standard_tags       = local.standard_tags
}

module "aws_security" {
  source = "../../providers/aws/security"

  environment            = "sandbox"
  vpc_id                 = module.aws_networking.vpc_id
  app_ports              = [80, 443, 8000, 3000]
  enable_strict_security = false
  standard_tags          = local.standard_tags
}

module "aws_compute_backend" {
  source = "../../providers/aws/compute"

  environment                = "sandbox"
  instance_prefix            = "sandbox-backend"
  subnet_ids                 = module.aws_networking.public_subnet_ids
  instance_type              = "t4g.micro"
  ami_id                     = ""
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 2
  desired_capacity           = 1
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 30
  root_volume_type           = "gp3"
  ecs_cluster_name           = "paymentform-cluster-sandbox"
  ecs_security_group_id      = module.aws_security.ecs_security_group_id
  region                     = "us-east-1"
  bucket_name                = module.cloudflare_r2.application_storage_bucket_name
  service_type               = "backend"
}

module "aws_ssm" {
  source = "../../providers/aws/ssm"

  environment       = "sandbox"
  app_key           = var.app_key
  redis_password    = var.redis_password
  turso_auth_token  = var.turso_auth_token
  turso_api_token   = var.turso_api_token
  neon_database_url = var.neon_database_url
  kms_key_id        = ""

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

# ============================================================================
# Cloudflare Infrastructure
# ============================================================================

module "cloudflare_r2" {
  source = "../../providers/cloudflare/r2"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  r2_bucket_name        = "paymentform-uploads"
  r2_public_bucket_name = ""
  r2_ssl_bucket_name    = "paymentform-ssl-config"

  cors_allowed_origins    = ["*"]
  lifecycle_rules_enabled = true
  ssl_cert_retention_days = 30

  worker_enabled       = true
  worker_route_pattern = "cdn.sandbox.paymentform.io/*"
  cloudflare_zone_id   = var.cloudflare_zone_id
}

module "cloudflare_kv_tenants" {
  source = "../../providers/cloudflare/kv"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.kv_store_api_token

  namespace_name    = "tenants"
  namespace_enabled = true
}

module "cloudflare_container_client" {
  source = "../../providers/cloudflare/containers"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "client"
  container_image   = var.client_container_image
  container_enabled = true

  domain_name    = "app.sandbox.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    NEXT_PUBLIC_API_URL = "https://api.sandbox.paymentform.io"
    NODE_ENV            = "production"
  }

  registry_url     = "ghcr.io"
  registry_username = "x-access-token"
  registry_password = var.ghcr_token
}

module "cloudflare_container_renderer" {
  source = "../../providers/cloudflare/containers"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "renderer"
  container_image   = var.renderer_container_image
  container_enabled = true

  domain_name    = "*.sandbox.paymentform.io"
  domain_proxied = false

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    R2_SSL_BUCKET_NAME       = module.cloudflare_r2.ssl_config_bucket_name
    R2_SSL_ENDPOINT          = module.cloudflare_r2.r2_endpoint
    R2_SSL_ACCESS_KEY_ID     = var.r2_ssl_access_key_id
    R2_SSL_SECRET_ACCESS_KEY = var.r2_ssl_secret_access_key
    NEXT_PUBLIC_API_URL      = "https://api.sandbox.paymentform.io"
    NODE_ENV                 = "production"
  }

  registry_url     = "ghcr.io"
  registry_username = "x-access-token"
  registry_password = var.ghcr_token
}

module "cloudflare_dns" {
  source = "../../providers/cloudflare/dns"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id

  domain_name        = "paymentform.io"
  api_subdomain      = "api.sandbox.paymentform.io"
  app_subdomain      = "app.sandbox.paymentform.io"
  renderer_subdomain = "*.sandbox.paymentform.io"

  api_origin_ips              = module.aws_compute_backend.instance_ips
  app_origin_ips              = []
  renderer_origin_ip          = ""
  app_container_endpoint      = module.cloudflare_container_client.container_endpoint
  renderer_container_endpoint = module.cloudflare_container_renderer.container_endpoint

  cloudflare_plan      = "free"
  enable_load_balancer = false
  enable_waf           = false
  enable_rate_limiting = false
  rate_limit_requests  = 100
  health_check_path    = "/health"
  notification_email   = ""
}

# ============================================================================
# Outputs
# ============================================================================

output "backend_instance_ips" {
  value = module.aws_compute_backend.instance_ips
}

output "client_container_endpoint" {
  value = module.cloudflare_container_client.container_endpoint
}

output "renderer_container_endpoint" {
  value = module.cloudflare_container_renderer.container_endpoint
}

output "api_hostname" {
  value = module.cloudflare_dns.api_hostname
}

output "app_hostname" {
  value = module.cloudflare_dns.app_hostname
}

output "renderer_hostname" {
  value = module.cloudflare_dns.renderer_hostname
}

output "r2_bucket_name" {
  value = module.cloudflare_r2.application_storage_bucket_name
}

output "ssl_config_bucket_name" {
  value = module.cloudflare_r2.ssl_config_bucket_name
}
