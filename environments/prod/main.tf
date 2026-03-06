# Production Environment Configuration

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
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "paymentform-terraform-locks"
  }
}

locals {
  resource_prefix = "paymentform-prod"

  standard_tags = {
    Environment = "prod"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }
}

# AWS Infrastructure
module "aws_networking" {
  source = "../../providers/aws/networking"

  environment         = "prod"
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  standard_tags       = local.standard_tags
}

module "aws_security" {
  source = "../../providers/aws/security"

  environment            = "prod"
  vpc_id                 = module.aws_networking.vpc_id
  app_ports              = [80, 443, 8000, 3000]
  enable_strict_security = true
  standard_tags          = local.standard_tags
}

module "aws_compute_backend" {
  source = "../../providers/aws/compute"

  environment                = "prod"
  instance_prefix            = "prod-backend"
  subnet_ids                 = module.aws_networking.public_subnet_ids
  instance_type              = "t4g.small"
  ami_id                     = ""
  key_pair_name              = ""
  min_size                   = 2
  max_size                   = 4
  desired_capacity           = 2
  scaling_cpu_threshold      = 60
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 50
  root_volume_type           = "gp3"
  ecs_cluster_name           = "paymentform-cluster-prod"
  ecs_security_group_id      = module.aws_security.ecs_security_group_id
  region                     = "us-east-1"
  bucket_name                = module.cloudflare_r2.application_storage_bucket_name
  service_type               = "backend"
  container_image_tag        = "latest"

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = en
    APP_FALLBACK_LOCALE = en

    BCRYPT_ROUNDS = 12

    LOG_CHANNEL              = stack
    LOG_STACK                = single
    LOG_DEPRECATIONS_CHANNEL = null
    LOG_LEVEL                = error

    DB_CONNECTION = "pgsql"
    DB_HOST       = var.db_host
    DB_PORT       = var.db_port
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"

    SESSION_DRIVER   = "database"
    SESSION_LIFETIME = 120
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = null

    BROADCAST_CONNECTION = "log"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "database"
    CACHE_STORE          = "database"


    REDIS_CLIENT   = phpredis
    REDIS_HOST     = var.redis_host
    REDIS_PORT     = var.redis_port
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = "smtp.mailgun.org"
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.aws_secret_access_key
    AWS_DEFAULT_REGION          = "us-east-1"
    AWS_BUCKET                  = "paymentform-uploads"
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = "https://paymentform-uploads.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://paymentform-uploads.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".paymentform.io"
    SESSION_DOMAIN           = ".paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.cloudflare_kv_tenants.api_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.cloudflare_kv_tenants.namespace_id
  }
}

module "aws_ssm" {
  source = "../../providers/aws/ssm"

  environment       = "prod"
  app_key           = var.app_key
  redis_password    = var.redis_password
  turso_auth_token  = var.turso_auth_token
  turso_api_token   = var.turso_api_token
  neon_database_url = var.neon_database_url
  kms_key_id        = ""

  db_password                   = var.db_password
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

# Cloudflare Infrastructure
module "cloudflare_r2" {
  source = "../../providers/cloudflare/r2"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  r2_bucket_name        = "paymentform-uploads"
  r2_public_bucket_name = ""
  r2_ssl_bucket_name    = "paymentform-ssl-config"

  cors_allowed_origins    = ["https://app.paymentform.io"]
  lifecycle_rules_enabled = true
  ssl_cert_retention_days = 30

  worker_enabled       = true
  worker_route_pattern = "cdn.paymentform.io/*"
  cloudflare_zone_id   = var.cloudflare_zone_id
}

module "cloudflare_kv_tenants" {
  source = "../../providers/cloudflare/kv"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.kv_store_api_token

  namespace_name    = "tenants"
  namespace_enabled = true
}

module "cloudflare_container_client" {
  source = "../../providers/cloudflare/containers"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "client"
  container_image   = var.client_container_image
  container_enabled = true

  domain_name    = "app.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "1"
  deployment_memory_mb = 1024
  instance_min_count   = 2

  container_env_vars = {
    NEXT_PUBLIC_API_URL = "https://api.paymentform.io"
    NODE_ENV            = "production"
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "cloudflare_container_renderer" {
  source = "../../providers/cloudflare/containers"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "renderer"
  container_image   = var.renderer_container_image
  container_enabled = true

  domain_name    = "*.paymentform.io"
  domain_proxied = false

  deployment_cpu       = "1"
  deployment_memory_mb = 1024
  instance_min_count   = 2

  container_env_vars = {
    R2_SSL_BUCKET_NAME       = module.cloudflare_r2.ssl_config_bucket_name
    R2_SSL_ENDPOINT          = module.cloudflare_r2.r2_endpoint
    R2_SSL_ACCESS_KEY_ID     = var.r2_ssl_access_key_id
    R2_SSL_SECRET_ACCESS_KEY = var.r2_ssl_secret_access_key
    NEXT_PUBLIC_API_URL      = "https://api.paymentform.io"
    NODE_ENV                 = "production"
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "cloudflare_container_backend" {
  source = "../../providers/cloudflare/containers"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "backend"
  container_image   = var.client_container_image
  container_enabled = true

  domain_name    = "api.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "1"
  deployment_memory_mb = 1024
  instance_min_count   = 2

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = en
    APP_FALLBACK_LOCALE = en

    BCRYPT_ROUNDS = 12

    LOG_CHANNEL              = stack
    LOG_STACK                = single
    LOG_DEPRECATIONS_CHANNEL = null
    LOG_LEVEL                = error

    DB_CONNECTION = "pgsql"
    DB_HOST       = var.db_host
    DB_PORT       = var.db_port
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"

    SESSION_DRIVER   = "database"
    SESSION_LIFETIME = 120
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = null

    BROADCAST_CONNECTION = "log"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "database"
    CACHE_STORE          = "database"


    REDIS_CLIENT   = phpredis
    REDIS_HOST     = var.redis_host
    REDIS_PORT     = var.redis_port
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = "smtp.mailgun.org"
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.aws_secret_access_key
    AWS_DEFAULT_REGION          = "us-east-1"
    AWS_BUCKET                  = "paymentform-uploads"
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = "https://paymentform-uploads.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://paymentform-uploads.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".paymentform.io"
    SESSION_DOMAIN           = ".paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.cloudflare_kv_tenants.api_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.cloudflare_kv_tenants.namespace_id
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "cloudflare_dns" {
  source = "../../providers/cloudflare/dns"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id

  domain_name        = "paymentform.io"
  api_subdomain      = "api.paymentform.io"
  app_subdomain      = "app.paymentform.io"
  renderer_subdomain = "*.paymentform.io"

  api_origin_ips              = module.aws_compute_backend.instance_ips
  app_origin_ips              = []
  renderer_origin_ip          = ""
  app_container_endpoint      = module.cloudflare_container_client.container_endpoint
  renderer_container_endpoint = module.cloudflare_container_renderer.container_endpoint

  cloudflare_plan      = "pro"
  enable_load_balancer = false
  enable_waf           = true
  enable_rate_limiting = true
  rate_limit_requests  = 100
  health_check_path    = "/health"
  notification_email   = "alerts@paymentform.io"
}

# Outputs
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
