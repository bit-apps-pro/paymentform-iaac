# Production US Region - Primary
# Primary region: us-east-1

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
    key            = "prod-us/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "paymentform-terraform-locks"
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  resource_prefix = "paymentform-prod-us"
  region          = "us-east-1"

  standard_tags = {
    Environment = "prod"
    Region      = "us-east-1"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }
}

module "aws_networking" {
  source = "../../providers/aws/networking"

  environment         = "prod-us"
  region              = local.region
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  standard_tags       = local.standard_tags
}

module "aws_security" {
  source = "../../providers/aws/security"

  environment            = "prod-us"
  vpc_id                 = module.aws_networking.vpc_id
  app_ports              = [80, 443, 8000, 3000]
  enable_strict_security = true
  standard_tags          = local.standard_tags
}

module "aws_database" {
  source = "../../providers/aws/database"

  environment       = "prod-us"
  ami_id            = var.postgres_ami_id
  subnet_ids        = module.aws_networking.public_subnet_ids
  security_group_id = module.aws_security.postgresql_security_group_id

  primary_instance_type = "t4g.small"
  replica_instance_type = "t4g.micro"
  primary_volume_size   = 50
  replica_volume_size   = 30
  volume_type           = "gp3"

  enable_replica   = true
  postgres_version = "16"
  db_name          = var.db_database
  db_user          = var.db_username
  db_password      = var.db_password

  r2_endpoint            = "https://${var.r2_backup_bucket_name}.r2.cloudflarestorage.com"
  r2_bucket_name         = var.r2_backup_bucket_name
  r2_access_key          = var.r2_backup_access_key
  r2_secret_key          = var.r2_backup_secret_key
  pgbackrest_cipher_pass = var.pgbackrest_cipher_pass

  standard_tags = local.standard_tags
  region        = local.region
  assign_eip    = true
}

module "aws_valkey" {
  source = "../../providers/aws/valkey"

  environment       = "prod-us"
  ami_id            = var.valkey_ami_id
  subnet_ids        = module.aws_networking.public_subnet_ids
  security_group_id = module.aws_security.valkey_security_group_id

  instance_type = "t4g.micro"
  node_count    = 2
  volume_size   = 20
  volume_type   = "gp3"

  cluster_password = var.redis_password
  memory_max       = "512mb"

  standard_tags = local.standard_tags
}

module "aws_compute_backend" {
  source = "../../providers/aws/compute"

  environment                = "prod-us"
  instance_prefix            = "prod-us-backend"
  subnet_ids                 = module.aws_networking.public_subnet_ids
  instance_type              = "t4g.small"
  ami_id                     = ""
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 4
  desired_capacity           = 2
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 50
  root_volume_type           = "gp3"
  ecs_cluster_name           = "paymentform-cluster-prod-us"
  ecs_security_group_id      = module.aws_security.ecs_security_group_id
  region                     = local.region
  bucket_name                = module.cloudflare_r2.application_storage_bucket_name
  service_type               = "backend"
  enable_pgbouncer          = true
  db_name                   = var.db_database
  db_password               = var.db_password
  db_read_replica_hosts     = concat(
    [module.aws_database.primary_endpoint],
    var.db_read_replica_endpoints
  )

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = 12

    LOG_CHANNEL              = "stack"
    LOG_STACK                = "single"
    LOG_DEPRECATIONS_CHANNEL = null
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = "127.0.0.1"
    DB_PORT       = 6432
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

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = module.aws_valkey.primary_endpoint
    REDIS_PORT     = 6379
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = "smtp.mailgun.org"
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.aws_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = module.cloudflare_r2.application_storage_bucket_name
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = module.cloudflare_r2.r2_endpoint
    AWS_CLOUDFRONT_URL          = module.cloudflare_r2.r2_endpoint

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

module "cloudflare_r2" {
  source = "../../providers/cloudflare/r2"

  environment           = "prod-us"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  r2_bucket_name        = "prod-paymentform-uploads"
  r2_public_bucket_name = ""
  r2_ssl_bucket_name    = "prod-paymentform-ssl-config"

  cors_allowed_origins    = ["https://app.paymentform.io"]
  lifecycle_rules_enabled = true
  ssl_cert_retention_days = 30

  worker_enabled       = false
  worker_route_pattern = ""
  cloudflare_zone_id   = var.cloudflare_zone_id
}

module "cloudflare_kv_tenants" {
  source = "../../providers/cloudflare/kv"

  environment           = "prod-us"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.kv_store_api_token

  namespace_name    = "tenants"
  namespace_enabled = true
}

output "region" {
  value = local.region
}

output "instance_ips" {
  value = module.aws_compute_backend.instance_ips
}

output "database_primary_endpoint" {
  value = module.aws_database.primary_endpoint
}

output "database_replica_endpoint" {
  value = module.aws_database.replica_endpoint
}

output "valkey_primary_endpoint" {
  value = module.aws_valkey.primary_endpoint
}
