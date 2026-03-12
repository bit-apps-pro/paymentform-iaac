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
  region = local.region
}

provider "aws" {
  alias  = "peer"
  region = length(var.peer_regions) > 0 ? var.peer_regions[0] : local.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  resource_prefix = "paymentform-p-us"
  region          = "us-east-1"

  standard_tags = {
    Environment = "prod"
    Region      = "us-east-1"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }
}

resource "aws_ssm_parameter" "ghcr_token" {
  name        = "/paymentform/prod-us/backend/GHCR_TOKEN"
  description = "GitHub Container Registry token for Docker image pull"
  type        = "SecureString"
  value       = var.ghcr_token
  overwrite   = true

  lifecycle {
    prevent_destroy = true
  }
}
# =============================================================================
# Networking (Shared)
# =============================================================================
module "paymentform_networking" {
  source = "../../../providers/aws/networking"

  environment         = "prod-us"
  region              = local.region
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  standard_tags       = local.standard_tags
}

module "vpc_peering" {
  source = "../../../providers/aws/vpc-peering"
  count  = length(var.peer_vpc_ids) > 0 ? length(var.peer_vpc_ids) : 0

  environment           = "prod-us"
  requester_vpc_id      = module.paymentform_networking.vpc_id
  requester_route_table_id = module.paymentform_networking.public_route_table_id
  requester_vpc_cidr    = "10.0.0.0/16"
  peer_vpc_id           = var.peer_vpc_ids[count.index]
  peer_route_table_id   = var.peer_route_table_ids[count.index]
  peer_vpc_cidr         = var.peer_vpc_cidrs[count.index]
  peer_region           = var.peer_regions[count.index]
  standard_tags         = local.standard_tags

  providers = {
    aws      = aws
    aws.peer = aws.peer
  }
}

# =============================================================================
# Security (Shared)
# =============================================================================
module "paymentform_security" {
  source = "../../../providers/aws/security"

  depends_on = [module.paymentform_alb]

  environment            = "prod-us"
  vpc_id                 = module.paymentform_networking.vpc_id
  app_ports              = [80, 443]
  enable_strict_security = true
  standard_tags          = local.standard_tags
  alb_security_group_id  = module.paymentform_alb.security_group_id
  cross_region_vpc_cidrs = var.peer_vpc_cidrs
}

# module "paymentform-database" {
#   source = "../../../providers/aws/database"

#   environment       = "prod-us"
#   ami_id            = var.postgres_ami_id
#   subnet_ids        = module.paymentform_networking.public_subnet_ids
#   security_group_id = module.paymentform_security.postgresql_security_group_id

#   primary_instance_type = "t4g.small"
#   replica_instance_type = "t4g.micro"
#   primary_volume_size   = 50
#   replica_volume_size   = 30
#   volume_type           = "gp3"

#   enable_replica   = true
#   postgres_version = "16"
#   db_name          = var.db_database
#   db_user          = var.db_username
#   db_password      = var.db_password

#   r2_endpoint            = "https://${var.r2_backup_bucket_name}.r2.cloudflarestorage.com"
#   r2_bucket_name         = var.r2_backup_bucket_name
#   r2_access_key          = var.r2_backup_access_key
#   r2_secret_key          = var.r2_backup_secret_key
#   pgbackrest_cipher_pass = var.pgbackrest_cipher_pass

#   standard_tags = local.standard_tags
#   region        = local.region
#   assign_eip    = true
# }

# =============================================================================
# PostgreSQL (Database - Backend Service)
# =============================================================================
module "postgres_primary_volume" {
  source = "../../../providers/aws/volume/postgres-primary"

  environment       = "prod-us"
  name              = "${local.resource_prefix}-database-primary"
  availability_zone = "${local.region}a"
  size              = 30
  volume_type       = "gp3"
  encrypted         = true
  iops              = 3000
  throughput        = 125
  device_name       = "/dev/sdf"
  instance_id       = ""
  standard_tags     = local.standard_tags
}


module "postgres_replica_volume" {
  source = "../../../providers/aws/volume/postgres-replica"

  environment       = "prod-us"
  name              = "${local.resource_prefix}-database-replica"
  availability_zone = "${local.region}b"
  size              = 30
  volume_type       = "gp3"
  encrypted         = true
  iops              = 3000
  throughput        = 125
  device_name       = "/dev/sdf"
  instance_id       = ""
  standard_tags     = local.standard_tags
}


# Pass volume IDs to database module (empty volumes list = use volume_ids instead)
module "postgres_database" {
  source = "../../../providers/aws/database"

  depends_on = [
    module.postgres_primary_volume,
    module.postgres_replica_volume
  ]

  environment       = "prod-us"
  name              = "${local.resource_prefix}-database"
  ami_id            = var.postgres_ami_id
  subnet_ids        = module.paymentform_networking.public_subnet_ids
  security_group_id = module.paymentform_security.postgresql_security_group_id

  primary_instance_type = "t4g.small"
  replica_instance_type = "t4g.micro"
  primary_volume_size   = 20
  replica_volume_size   = 20
  volume_type           = "gp3"

  enable_replica   = true
  postgres_version = "17"
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

  peer_vpc_cidrs = var.peer_vpc_cidrs

  # Pass pre-created volume IDs (empty volumes list)
  volumes = []
  volume_ids = {
    postgresql-primary-data = module.postgres_primary_volume.volume_id
    postgresql-replica-data = module.postgres_replica_volume.volume_id
  }
}

module "paymentform_cache" {
  source = "../../../providers/aws/valkey"

  environment       = "prod-us"
  name              = "${local.resource_prefix}-cache"
  ami_id            = var.valkey_ami_id
  subnet_ids        = module.paymentform_networking.public_subnet_ids
  security_group_id = module.paymentform_security.valkey_security_group_id

  instance_type = "t4g.small"
  node_count    = 1
  volume_size   = 20
  volume_type   = "gp3"

  cluster_password = var.redis_password
  memory_max       = "512mb"

  standard_tags = local.standard_tags
}

module "paymentform_backend" {
  source = "../../../providers/aws/compute"

  depends_on = [
    module.paymentform_alb,
    module.paymentform_security
  ]

  environment                = "prod-us"
  instance_prefix            = "${local.resource_prefix}-backend"
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  instance_type              = "t4g.small"
  ami_id                     = "ami-06fdf1c06301d49be"
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 4
  desired_capacity           = 1
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 50
  root_volume_type           = "gp3"
  ecs_cluster_name           = "${local.resource_prefix}-cluster"
  ecs_security_group_id      = module.paymentform_security.ecs_security_group_id
  region                     = local.region
  bucket_name                = module.paymentform_storage_application.bucket_name
  service_type               = "backend"
  enable_pgbouncer           = true
  db_name                    = var.db_database
  ghcr_username              = var.ghcr_username
  db_password                = var.db_password
  container_image            = var.backend_container_image
  alb_target_group_arn       = module.paymentform_alb.target_group_arn
  db_read_replica_hosts = concat(
    [module.postgres_database.primary_endpoint],
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
    DB_HOST_WRITE = "127.0.0.1"
    DB_HOST_READ  = length(var.db_read_replica_endpoints) > 0 ? var.db_read_replica_endpoints[0] : module.postgres_database.primary_endpoint
    DB_PORT       = 6432
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = 120
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = null

    BROADCAST_CONNECTION = "redis"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "redis"
    CACHE_STORE          = "redis"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = module.paymentform_cache.primary_endpoint
    REDIS_PORT     = 6379
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.aws_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = module.paymentform_storage_application.bucket_name
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"

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

    KV_STORE_API_URL      = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id
  }
}

module "paymentform_renderer" {
  source = "../../../providers/aws/compute"

  depends_on = [
    module.paymentform_alb,
    module.paymentform_security
  ]

  environment                = "prod-us"
  instance_prefix            = "${local.resource_prefix}-renderer"
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  instance_type              = "t4g.small"
  ami_id                     = "ami-06fdf1c06301d49be"
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 4
  desired_capacity           = 1
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 20
  root_volume_type           = "gp3"
  ecs_cluster_name           = "${local.resource_prefix}-cluster"
  ecs_security_group_id      = module.paymentform_security.ecs_security_group_id
  region                     = local.region
  bucket_name                = module.paymentform_storage_application.bucket_name
  service_type               = "renderer"
  enable_pgbouncer           = false
  ghcr_username              = var.ghcr_username
  container_image            = var.renderer_container_image
  alb_target_group_arn       = module.paymentform_alb.renderer_target_group_arn

  container_env_vars = {
    R2_SSL_BUCKET_NAME       = module.paymentform_storage_ssl_config.bucket_name
    R2_SSL_ENDPOINT          = module.paymentform_storage_ssl_config.bucket_domain
    R2_SSL_ACCESS_KEY_ID     = var.r2_ssl_access_key_id
    R2_SSL_SECRET_ACCESS_KEY = var.r2_ssl_secret_access_key
    API_URL                  = "https://api.paymentform.io"
    DOMAIN                   = "https://app.paymentform.io"
    KV_STORE_BASE_URL        = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_NAMESPACE_ID    = module.paymentform_kv_store.namespace_id
    KV_STORE_API_TOKEN       = var.kv_store_api_token
    STRIPE_KEY               = var.stripe_public_key
    RESERVED_SUBDOMAINS      = "www,admin,api,app,dev,test"
    NODE_ENV                 = "production"
  }
}

module "paymentform_storage_application" {
  source = "../../../providers/cloudflare/r2/application-storage"

  environment           = "prod-us"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = "${local.resource_prefix}-uploads"
}

module "paymentform_storage_ssl_config" {
  source = "../../../providers/cloudflare/r2/ssl-config"

  environment           = "prod-us"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = "${local.resource_prefix}-ssl-config"
  enabled               = true
}

module "paymentform_storage_cdn_worker" {
  source = "../../../providers/cloudflare/r2/cdn-worker"

  environment           = "prod-us"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  worker_enabled          = false
  worker_route_pattern    = "app.paymentform.io/*"
  cors_allowed_origins    = ["https://app.paymentform.io"]
  application_bucket_name = module.paymentform_storage_application.bucket_name
}

module "paymentform_kv_store" {
  source = "../../../providers/cloudflare/kv"

  environment           = "paymenform"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  namespace_name     = "tenants"
  namespace_enabled  = true
  deploy_worker      = true
  worker_path        = "${path.root}/../../../../kv-store"
  kv_store_api_token = var.kv_store_api_token
}

module "paymentform_alb" {
  source = "../../../providers/aws/alb"

  environment = "prod-us"
  name        = "${local.resource_prefix}-alb"
  vpc_id      = module.paymentform_networking.vpc_id
  subnet_ids  = module.paymentform_networking.public_subnet_ids

  target_port                = 80
  health_check_path          = "/health"
  enable_deletion_protection = true
  api_hostname               = "api.paymentform.io"

  standard_tags = local.standard_tags
}

module "paymentform_client" {
  source = "../../../providers/cloudflare/containers"

  environment           = "prod-us"
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

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    API_URL         = "https://api.paymentform.io"
    DOMAIN          = "https://app.paymentform.io"
    COOKIE_DOMAIN   = ".paymentform.io"
    FORM_RENDER_URL = "https://renderer.paymentform.io/"
    STRIPE_KEY      = var.stripe_public_key
    NODE_ENV        = "production"
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "paymenform_dns" {
  source = "../../../providers/cloudflare/dns"

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

  api_cname      = module.paymentform_alb.alb_dns_name
  app_origin_ips = []
  # renderer_origin_ip          = module.paymentform_alb.alb_dns_name
  # app_container_endpoint      = module.paymentform_client.container_endpoint
  renderer_container_endpoint = module.paymentform_alb.alb_dns_name

  cloudflare_plan      = "free"
  enable_load_balancer = false
  enable_waf           = false
  enable_rate_limiting = false
  rate_limit_requests  = 100
  health_check_path    = "/health"
  notification_email   = ""
}
