# Production Environment - Primary Region: us-east-1

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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

provider "aws" {
  region = local.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "hcloud" {
  token = var.hetzner_api_token
}

data "aws_caller_identity" "current" {}

locals {
  resource_prefix = "paymentform-prod"
  region          = "us-east-1"

  standard_tags = {
    Environment = "prod"
    Region      = "us-east-1"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }

  hetzner_ssh_key_id = try(data.hcloud_ssh_key.existing[0].id, try(hcloud_ssh_key.shared[0].id, ""))
}

resource "aws_ssm_parameter" "ghcr_token" {
  name        = "/paymentform/prod/backend/GHCR_TOKEN"
  description = "GitHub Container Registry token for Docker image pull"
  type        = "SecureString"
  value       = var.ghcr_token
  overwrite   = true

  lifecycle {
    prevent_destroy = false
  }
}

# =============================================================================
# Cloudflare R2 — Admin DB backups (barman-cloud-backup target)
# =============================================================================
# Dedicated bucket for the local PostgreSQL instance running on the Hetzner
# admin server. Separate from the primary DB's pgbackrest bucket so retention
# policies and access can evolve independently. Reuses existing
# `backup_storage_*` R2 credentials — no new tokens.
resource "cloudflare_r2_bucket" "admin_db_backup" {
  account_id = var.cloudflare_account_id
  name       = "prod-admin-db-backup"
}

# =============================================================================
# Networking
# =============================================================================
module "paymentform_networking" {
  source = "../../providers/aws/networking"

  environment         = "prod"
  region              = local.region
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  standard_tags       = local.standard_tags
}

# =============================================================================
# Security
# =============================================================================
module "paymentform_security" {
  source = "../../providers/aws/security"

  environment            = "prod"
  vpc_id                 = module.paymentform_networking.vpc_id
  app_ports              = [80, 443]
  enable_strict_security = true
  standard_tags          = local.standard_tags
  nlb_security_group_ids = [
    module.paymentform_nlb_renderer.security_group_id,
  ]
  alb_security_group_ids = [module.paymentform_alb_backend.security_group_id]
  cross_region_vpc_cidrs = var.peer_vpc_cidrs
}

# =============================================================================
# PostgreSQL (Database)
# =============================================================================
module "postgres_primary_volume" {
  source = "../../providers/aws/volume/postgres-primary"

  environment       = "prod"
  name              = "${local.resource_prefix}-database-primary"
  availability_zone = "${local.region}a"
  size              = 30
  volume_type       = "gp3"
  encrypted         = true
  iops              = 4000
  throughput        = 250
  device_name       = "/dev/sdf"
  instance_id       = ""
  standard_tags     = local.standard_tags
}

module "postgres_replica_volume" {
  source = "../../providers/aws/volume/postgres-replica"

  environment       = "prod"
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

# =============================================================================
# Cloudflare Tunnel — DB Primary (exposes Postgres 5432 to Hetzner servers)
# =============================================================================
module "tunnel_db" {
  source = "../../providers/cloudflare/tunnel-db"

  cloudflare_account_id = var.cloudflare_account_id
  resource_prefix       = "${local.resource_prefix}-db"
  zone_id               = var.cloudflare_zone_id
  domain_name           = "paymentform.io"
  allowed_cidrs         = []
}

module "postgres_database" {
  source = "../../providers/aws/database"

  depends_on = [
    module.postgres_primary_volume,
    module.postgres_replica_volume
  ]

  environment       = "prod"
  name              = "${local.resource_prefix}-database"
  ami_id            = var.postgres_ami_id
  subnet_ids        = module.paymentform_networking.public_subnet_ids
  security_group_id = module.paymentform_security.postgresql_security_group_id

  primary_instance_type = "t4g.medium"
  replica_instance_type = "t4g.small"
  primary_volume_size   = 20
  replica_volume_size   = 20
  volume_type           = "gp3"

  enable_replica   = false
  postgres_version = "17"
  db_name          = var.db_database
  db_user          = var.db_username
  db_password      = var.db_password

  database_backup_bucket_endpoint      = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
  database_backup_bucket_name          = var.backup_storage_bucket_name
  database_backup_bucket_access_key_id = var.backup_storage_access_key_id
  database_backup_bucket_access_key    = var.backup_storage_access_key
  pgbackrest_cipher_pass               = var.pgbackrest_cipher_pass

  # Cloudflared tunnel disabled on primary; admin access goes through SSM Session Manager.
  # Set to "" so the userdata `if tunnel_token != ""` guard skips the cloudflared install.
  tunnel_token = ""

  standard_tags = local.standard_tags
  region        = local.region
  assign_eip    = true

  peer_vpc_cidrs    = var.peer_vpc_cidrs
  admin_db_password = var.admin_db_password

  volumes = []
  volume_ids = {
    postgresql-primary-data = module.postgres_primary_volume.volume_id
    postgresql-replica-data = module.postgres_replica_volume.volume_id
  }
}

module "paymentform_cache" {
  source = "../../providers/aws/valkey"

  environment       = "prod"
  name              = "${local.resource_prefix}-cache"
  region            = local.region
  ami_id            = var.valkey_ami_id
  subnet_ids        = module.paymentform_networking.public_subnet_ids
  security_group_id = module.paymentform_security.valkey_security_group_id

  instance_type = "t4g.medium"
  node_count    = 1
  volume_size   = 20
  volume_type   = "gp3"

  cluster_password = var.redis_password
  memory_max       = "2.5gb"

  standard_tags = local.standard_tags
}

# =============================================================================
# SQS — Laravel queues (default, webhooks, exports, tenant-provisioning)
# =============================================================================
# Logical queue names match Laravel's `--queue=` worker flags and code-level
# `->onQueue('...')` dispatches. AWS-side names are prefixed so multiple
# environments can share an AWS account without collisions. The Laravel SQS
# driver joins SQS_PREFIX (account URL) + queue name; SQS_SUFFIX is used as the
# resource-prefix bridge so application code keeps using the unprefixed names.
module "paymentform_sqs" {
  source = "../../providers/aws/sqs"

  environment = "prod"
  # Laravel SQS driver appends `SQS_SUFFIX` to every dispatched queue name to
  # build the URL — AWS resources MUST be named to match. Suffix (not prefix)
  # is the only Laravel-supported namespacing knob.
  name_suffix = "-${local.resource_prefix}"
  queues      = ["default", "webhooks", "exports", "tenant-provisioning"]

  # Per-queue visibility timeout = 2x worker --timeout (defined in
  # backend/.docker/*/Dockerfile.backend-base SUPERVISOR_*_QUEUE_COMMAND).
  # Headroom for jobs that legitimately straddle the timeout boundary while
  # still recovering quickly when a worker crashes mid-job. Without overrides
  # every queue would inherit the module default (600s) and a stuck 90s job
  # would block redelivery for 10 minutes.
  queue_visibility_overrides = {
    default             = 180 # 2 * 90
    webhooks            = 180 # 2 * 90
    exports             = 600 # 2 * 300
    tenant-provisioning = 360 # 2 * 180
  }
  standard_tags = local.standard_tags
}

# IAM policy granting backend EC2 instances permission to publish/consume
# their own SQS queues. Scoped to the queue ARNs created above — no wildcard.
resource "aws_iam_policy" "backend_sqs_access" {
  name        = "${local.resource_prefix}-backend-sqs-access"
  description = "Allow backend EC2 instances to use the Laravel SQS queues."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:SendMessageBatch",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:DeleteMessageBatch",
          "sqs:ChangeMessageVisibility",
          "sqs:ChangeMessageVisibilityBatch",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = module.paymentform_sqs.all_arns
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backend_sqs_access" {
  role       = module.paymentform_backend.instance_role_name
  policy_arn = aws_iam_policy.backend_sqs_access.arn
}

module "paymentform_backend" {
  source = "../../providers/aws/compute-alb"

  depends_on = [
    module.paymentform_alb_backend,
    module.paymentform_security
  ]

  environment             = "prod"
  instance_prefix         = "${local.resource_prefix}-backend"
  subnet_ids              = module.paymentform_networking.public_subnet_ids
  instance_type           = "c7g.large"
  ami_id                  = "ami-06fdf1c06301d49be"
  key_pair_name           = ""
  min_size                = 2
  max_size                = 8
  desired_capacity        = 2
  alb_arn_suffix          = module.paymentform_alb_backend.alb_arn_suffix
  target_group_arn_suffix = module.paymentform_alb_backend.target_group_arn_suffix
  standard_tags           = local.standard_tags
  detailed_monitoring     = true
  ebs_optimized           = true
  root_volume_size        = 50
  root_volume_type        = "gp3"
  ecs_cluster_name        = "${local.resource_prefix}-cluster"
  ecs_security_group_id   = module.paymentform_security.ecs_security_group_id
  region                  = local.region
  # bucket_name                = module.paymentform_storage_application.bucket_names["us"]
  service_type                             = "backend"
  ghcr_username                            = var.ghcr_username
  container_image                          = var.backend_container_image
  on_demand_base_capacity                  = 2
  on_demand_percentage_above_base_capacity = 0
  spot_instance_types                      = ["c7g.large", "c6g.large", "m7g.large", "m6g.large"]
  spot_allocation_strategy                 = "capacity-optimized"
  capacity_rebalance                       = true
  alb_target_group_arns = [
    module.paymentform_alb_backend.target_group_arn,
  ]
  deploy_script_content = file("${path.module}/../../../backend/.github/scripts/deploy-ec2.sh")

  # Sockudo + worker sidecars. Sockudo binds 127.0.0.1:6001 on host network so
  # the backend Caddy `/ws/*` handler reaches it via loopback. Cross-instance
  # fanout uses the same Valkey already wired as REDIS_HOST for the app.
  worker_container_image  = var.worker_container_image
  sockudo_enabled         = true
  valkey_host             = module.paymentform_cache.primary_endpoint
  valkey_password         = var.redis_password
  reverb_app_id           = var.reverb_app_id
  reverb_app_key          = var.reverb_app_key
  reverb_app_secret       = var.reverb_app_secret
  sockudo_allowed_origins = ["https://app.paymentform.io"]

  container_env_vars = merge({
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    APP_DOMAIN        = "api.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = 12

    # Ship every log line to the Cloudflare status worker (D1). No local file
    # output: EC2 ASG instances are ephemeral and storage_path('logs/') is not
    # collected. STATUS_LOG_* below tunes sampling/retention.
    LOG_CHANNEL              = "status_worker"
    LOG_DEPRECATIONS_CHANNEL = null
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.postgres_database.primary_endpoint
    DB_PORT       = 6432
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"
    TENANT_DB_AUTH_TOKEN        = var.tenant_db_auth_token

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = 10080
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = ".paymentform.io"

    BROADCAST_CONNECTION = "reverb"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "sqs"
    CACHE_STORE          = "redis"

    # SQS via EC2 instance role — SQS_KEY/SQS_SECRET intentionally unset.
    # AppServiceProvider::boot() pins `queue.connections.sqs.credentials` to
    # an explicit InstanceProfileProvider in that case so the SqsClient skips
    # the AWS SDK's default chain (which would otherwise read
    # AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY env first — those hold
    # Cloudflare R2 credentials and SQS would 403). The IAM policy attached
    # to the backend instance role grants Send/Receive/Delete on these
    # queues; see aws_iam_policy.backend_sqs_access below.
    SQS_PREFIX = "https://sqs.${local.region}.amazonaws.com/${data.aws_caller_identity.current.account_id}"
    SQS_QUEUE  = "default"
    SQS_SUFFIX = module.paymentform_sqs.name_suffix

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = module.paymentform_cache.primary_endpoint
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = var.redis_password

    # Backend now broadcasts to the in-host Sockudo sidecar (127.0.0.1:6001)
    # over loopback. Reverb supervisord entry is being retired in a separate
    # cutover commit; keeping REVERB_* env names because the Laravel reverb
    # broadcaster reads them as its Pusher-protocol connection config.
    REVERB_APP_ID          = var.reverb_app_id
    REVERB_APP_KEY         = var.reverb_app_key
    REVERB_APP_SECRET      = var.reverb_app_secret
    REVERB_HOST            = "localhost"
    REVERB_PORT            = "6001"
    REVERB_SCHEME          = "http"
    REVERB_SCALING_ENABLED = "false"
    # activity_timeout 30s (default) is too aggressive — connections silently drop after the
    # client's pong cycle exceeds 30s under load. 120s gives breathing room without leaking
    # stale connections.
    REVERB_APP_PING_INTERVAL    = "60"
    REVERB_APP_ACTIVITY_TIMEOUT = "120"

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.upload_storage_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.upload_storage_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = "paymentform-uploads-us"
    AWS_BUCKET_EU               = "paymentform-uploads-eu"
    AWS_BUCKET_AP               = "paymentform-uploads-ap"
    AWS_USE_PATH_STYLE_ENDPOINT = "true"
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_ENDPOINT_EU             = "https://${var.cloudflare_account_id}.eu.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CDN_URL                 = "https://cdn-us.paymentform.io"
    AWS_CDN_URL_EU              = "https://cdn-eu.paymentform.io"
    AWS_CDN_URL_AP              = "https://cdn-ap.paymentform.io"
    AWS_ACCESS_KEY_ID_EU        = var.upload_storage_access_key_id_eu
    AWS_SECRET_ACCESS_KEY_EU    = var.upload_storage_secret_access_key_eu
    AWS_ACCESS_KEY_ID_AP        = var.upload_storage_access_key_id_ap
    AWS_SECRET_ACCESS_KEY_AP    = var.upload_storage_secret_access_key_ap

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST,GET,OPTIONS,PUT,DELETE,PATCH"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant,X-Embed"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    # Sanctum matches this via Str::is — patterns are globs, not cookie-domain
    # syntax. Leading dot here matches NOTHING (e.g. ".paymentform.io/*" does
    # not match "app.paymentform.io/"). Must be an explicit host list. The
    # leading-dot cookie-scope semantics belong on SESSION_DOMAIN only.
    SANCTUM_STATEFUL_DOMAINS = "paymentform.io,app.paymentform.io,api.paymentform.io"

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

    OTEL_SDK_DISABLED           = "true"
    OTEL_SERVICE_NAME           = "PaymentForm"
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_LOGS_EXPORTER          = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"

    ALERT_EMAIL_ENABLED     = false
    ALERT_SLACK_ENABLED     = false
    ALERT_SLACK_CHANNEL     = "#alerts"
    ALERT_WEBHOOK_ENABLED   = false
    ALERT_SLACK_WEBHOOK_URL = ""
    ALERT_WEBHOOK_URL       = ""
    ALERT_WEBHOOK_SECRET    = ""
    STATUS_LOG_INGEST_URL   = "https://status.paymentform.io/api/logs/batch"
    STATUS_LOG_INGEST_TOKEN = var.status_log_ingest_token
    }, module.postgres_database.replica_endpoint != null ? {
    DB_HOST_WRITE = module.postgres_database.primary_endpoint
    DB_HOST_READ  = module.postgres_database.replica_endpoint
  } : {})

  caddy_env_vars = {
    APP_DOMAIN                       = "api.paymentform.io"
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
    CADDY_LOG_LEVEL                  = "warn"
    ACME_EMAIL                       = "hello@paymentform.io"
    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    NUM_THREADS                      = "16"
    OCTANE_WORKERS                   = "6"
    OCTANE_ENABLED                   = false
    CADDY_SERVER_LOG_LEVEL           = "warn"
    CADDY_SERVER_ADMIN_PORT          = "2019"
    CADDY_SERVER_ADMIN_HOST          = "localhost"
    CADDY_SERVER_LOGGER              = "json"
  }
}

module "paymentform_renderer" {
  source = "../../providers/aws/compute-nlb"

  depends_on = [
    module.paymentform_nlb_renderer,
    module.paymentform_security
  ]

  environment                   = "prod"
  instance_prefix               = "${local.resource_prefix}-renderer"
  subnet_ids                    = module.paymentform_networking.public_subnet_ids
  instance_type                 = "c7g.medium"
  ami_id                        = "ami-06fdf1c06301d49be"
  key_pair_name                 = ""
  min_size                      = 1
  max_size                      = 4
  desired_capacity              = 1
  scaling_memory_threshold      = 70
  scaling_down_memory_threshold = 40
  standard_tags                 = local.standard_tags
  detailed_monitoring           = true
  ebs_optimized                 = true
  root_volume_size              = 20
  root_volume_type              = "gp3"
  ecs_cluster_name              = "${local.resource_prefix}-cluster"
  ecs_security_group_id         = module.paymentform_security.ecs_security_group_id
  region                        = local.region
  service_type                  = "renderer"
  ghcr_username                 = var.ghcr_username
  container_image               = var.renderer_container_image
  alb_target_group_arns = [
    module.paymentform_nlb_renderer.https_target_group_arn,
    module.paymentform_nlb_renderer.http_target_group_arn,
  ]
  deploy_script_content = file("${path.module}/../../../renderer/.github/scripts/deploy-ec2.sh")

  spot_instance_percentage = 75
  on_demand_base_capacity  = 1

  container_env_vars = {
    API_URL               = "https://api.paymentform.io"
    DOMAIN                = "paymentform.io"
    KV_STORE_BASE_URL     = "https://paymentform-tenant-validator-prod.bitapps.workers.dev"
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    STRIPE_KEY            = var.stripe_public_key
    RESERVED_SUBDOMAINS   = "www, api, admin, app, mail, ftp, smtp, imap, pop,dns, cdn, static, assets, blog, docs, help, support,status, test, staging, dev, development, develop, developer,localhost, email, webmail, calendar, files, git, svn, chat,wiki, forum, shop, store, auth, metrics, monitoring"
    NODE_ENV              = "production"
  }

  caddy_env_vars = {
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
    ACME_EMAIL                       = "hello@paymentform.io"
    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    KV_STORE_BASE_URL                = "https://paymentform-tenant-validator-prod.bitapps.workers.dev"
    KV_STORE_NAMESPACE_ID            = module.paymentform_kv_store.namespace_id
    KV_STORE_API_TOKEN               = var.kv_store_api_token
    DOMAIN                           = "paymentform.io"
    NODE_ENV                         = "production"
    ENVIRONMENT                      = "production"
  }
}

module "paymentform_storage_application" {
  source = "../../providers/cloudflare/r2/application-storage"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  bucket_name_prefix    = "paymentform-uploads"
}

module "paymentform_storage_ssl_config" {
  source = "../../providers/cloudflare/r2/ssl-config"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = "${local.resource_prefix}-ssl-config"
  enabled               = true
}

module "paymentform_storage_cdn" {
  source = "../../providers/cloudflare/r2/cdn-worker"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  worker_enabled = true
  regional_buckets = {
    for region in keys(module.paymentform_storage_application.bucket_names) : region => {
      bucket_name  = module.paymentform_storage_application.bucket_names[region]
      jurisdiction = module.paymentform_storage_application.bucket_jurisdictions[region]
    }
  }
  domain_prefix    = "cdn"
  base_domain      = "paymentform.io"
  regional_domains = { us = "cdn-us.paymentform.io", ap = "cdn-ap.paymentform.io" }
}

# =============================================================================
# Renderer static-asset CDN
# =============================================================================
# Bucket + native R2 public custom domain that fronts the Next.js renderer's
# `_next/static/<buildId>/...` and `public/...` paths at
# static.paymentform.io. CI uploads on every push; HTML stays on origin
# so canonical-domain routing inside the renderer process is unaffected.
# See `iaac/providers/cloudflare/r2/renderer-static/README.md`.
module "paymentform_renderer_static_cdn" {
  source = "../../providers/cloudflare/r2/renderer-static"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  bucket_name           = "paymentform-renderer-static"
  custom_domain         = var.renderer_static_cdn_domain
  cors_origins          = var.renderer_static_cors_origins
  static_retention_days = 30
}

module "paymentform_kv_store" {
  source = "../../providers/cloudflare/kv"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  namespace_name     = "tenants"
  namespace_enabled  = true
  deploy_worker      = true
  worker_path        = "${path.root}/../../../kv-store"
  kv_store_api_token = var.kv_store_api_token
}

# =============================================================================
# ACM Certificate for Backend API
# =============================================================================
module "paymentform_acm_backend" {
  source = "../../providers/aws/acm"

  domain_name               = "api.paymentform.io"
  subject_alternative_names = []
  cloudflare_zone_id        = var.cloudflare_zone_id
  standard_tags             = local.standard_tags
}

# =============================================================================
# ALB for Backend API
# =============================================================================
module "paymentform_alb_backend" {
  source = "../../providers/aws/alb"

  environment                = "prod"
  prefix                     = "${local.resource_prefix}-backend"
  service_label              = "bknd"
  vpc_id                     = module.paymentform_networking.vpc_id
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  enable_deletion_protection = true
  standard_tags              = local.standard_tags
  acm_certificate_arn        = module.paymentform_acm_backend.certificate_arn
  alert_webhook_url          = var.alert_webhook_url
}

# NLB for renderer - *.paymentform.io → port 80/443 → renderer containers
module "paymentform_nlb_renderer" {
  source = "../../providers/aws/nlb"

  environment                = "prod"
  prefix                     = "${local.resource_prefix}-renderer"
  service_label              = "rndr"
  vpc_id                     = module.paymentform_networking.vpc_id
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  enable_deletion_protection = false
  standard_tags              = local.standard_tags
  alert_webhook_url          = var.alert_webhook_url
}

module "paymentform_client" {
  source = "../../providers/cloudflare/containers"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "client"
  container_image   = var.client_container_image
  container_enabled = false

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

# =============================================================================
# Hetzner Networks (private networking per zone)
# =============================================================================
data "hcloud_ssh_key" "existing" {
  count = var.hetzner_ssh_key_name != "" ? 1 : 0
  name  = var.hetzner_ssh_key_name
}

resource "hcloud_ssh_key" "shared" {
  count      = var.hetzner_ssh_key_name == "" && var.hetzner_ssh_public_key != "" ? 1 : 0
  name       = "${local.resource_prefix}-shared-key"
  public_key = var.hetzner_ssh_public_key
}

module "hetzner_network_eu" {
  source = "../../providers/hetzner/network"

  enabled         = false
  environment     = "prod"
  resource_prefix = "paymentform-p-eu"
  network_zone    = "eu-central"
  ip_range        = "10.10.0.0/16"
  subnet_ip_range = "10.10.1.0/24"
  standard_tags   = local.standard_tags
}

module "hetzner_network_ap" {
  source = "../../providers/hetzner/network"

  enabled         = false
  environment     = "prod"
  resource_prefix = "paymentform-p-sg"
  network_zone    = "ap-southeast"
  ip_range        = "10.20.0.0/16"
  subnet_ip_range = "10.20.1.0/24"
  standard_tags   = local.standard_tags
}

# =============================================================================
# Hetzner — EU Admin (HEL1 Helsinki) - Admin app (Traefik + admin + valkey)
# =============================================================================
module "hetzner_admin_hel1" {
  source = "../../providers/hetzner/admin-server"

  enabled              = true
  environment          = "prod"
  resource_prefix      = "paymentform-p-eu-admin"
  region               = "eu-hel1"
  location             = "hel1"
  server_type          = "ccx13"
  server_image         = "ubuntu-24.04"
  ssh_key_id           = local.hetzner_ssh_key_id
  os_user_public_key   = var.hetzner_ssh_public_key
  os_username          = "paymentform"
  ssh_private_key_path = var.hetzner_ssh_private_key_path
  admin_cidr_blocks    = var.admin_cidr_blocks
  ghcr_username        = var.ghcr_username
  ghcr_token           = var.ghcr_token
  network_id           = tostring(module.hetzner_network_eu.network_id)

  admin_image     = var.admin_container_image
  traefik_host    = "paymentform.io"
  acme_email      = var.acme_email
  valkey_password = var.valkey_password

  # Local postgres on the admin box (admin's own data: users, sessions, audit)
  local_db_database = "paymentform_admin"
  local_db_username = "admin"
  local_db_password = var.admin_local_db_password

  # Weekly barman-cloud-backup of the local postgres to a dedicated R2 bucket.
  # Reuses the existing backup_storage_* credentials (single R2 token covers
  # both pgbackrest and barman use cases).
  backup_replication_password = var.admin_backup_replication_password
  backup_bucket_name          = cloudflare_r2_bucket.admin_db_backup.name
  backup_bucket_endpoint      = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
  backup_bucket_access_key_id = var.backup_storage_access_key_id
  backup_bucket_access_key    = var.backup_storage_access_key

  deploy_script_content = file("${path.module}/../../../admin/.github/scripts/deploy-hetzner.sh")
  compose_file_content  = file("${path.module}/../../../admin/docker-compose.yml")

  admin_container_env_vars = {
    APP_NAME  = "Payment Form Admin"
    APP_ENV   = "production"
    APP_URL   = "https://admin.paymentform.io"
    APP_KEY   = var.app_key
    APP_DEBUG = "false"

    LOG_CHANNEL              = "status_worker"
    LOG_DEPRECATIONS_CHANNEL = ""
    LOG_LEVEL                = "error"

    # Default Laravel connection -> local postgres (admin's own data:
    # users, sessions, audit). Reached over the traefik-public docker network
    # by container DNS name `postgres`.
    DB_CONNECTION = "pgsql"
    DB_HOST       = "postgres"
    DB_PORT       = "5432"
    DB_DATABASE   = "paymentform_admin"
    DB_USERNAME   = "admin"
    DB_PASSWORD   = var.admin_local_db_password

    # Secondary connection -> AWS primary (tenant-data reads).
    # Bound in admin/config/database.php as `connections.primary`. Uses the
    # restricted paymentform_admin role created at primary bootstrap.
    BACKEND_DB_CONNECTION = "pgsql"
    BACKEND_DB_HOST       = module.postgres_database.primary_public_ip
    BACKEND_DB_PORT       = "5432"
    BACKEND_DB_DATABASE   = var.db_database
    BACKEND_DB_USERNAME   = "paymentform_admin"
    BACKEND_DB_PASSWORD   = var.admin_db_password

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = "10080"
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = "admin.paymentform.io"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = "valkey"
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = var.valkey_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    CORS_ALLOWED_ORIGINS = "https://admin.paymentform.io"
    CORS_ALLOWED_METHODS = "POST,GET,OPTIONS,PUT,DELETE,PATCH"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token,X-XSRF-TOKEN,Accept,Origin"

    QUEUE_CONNECTION = "redis"
    CACHE_STORE      = "redis"
  }

  standard_tags = local.standard_tags
}

# Allow admin server to reach primary PostgreSQL (avoids cycle via module inputs)
resource "aws_security_group_rule" "postgresql_ingress_from_admin" {
  count             = module.hetzner_admin_hel1.enabled ? 1 : 0
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["${module.hetzner_admin_hel1.ipv4_address}/32"]
  security_group_id = module.paymentform_security.postgresql_security_group_id
  description       = "Allow PostgreSQL from Hetzner admin server"
}

# =============================================================================
# Hetzner — EU (HEL1 Helsinki)
# =============================================================================
module "hetzner_backend_hel1" {
  source = "../../providers/hetzner/server"

  enabled              = false
  environment          = "prod"
  resource_prefix      = "paymentform-p-eu"
  region               = "eu-hel1"
  location             = "hel1"
  server_type          = "ccx13"
  server_image         = "ubuntu-24.04"
  ssh_key_id           = local.hetzner_ssh_key_id
  os_user_public_key   = var.hetzner_ssh_public_key
  ssh_private_key_path = var.hetzner_ssh_private_key_path
  admin_cidr_blocks    = var.admin_cidr_blocks
  ghcr_username        = var.ghcr_username
  ghcr_token           = var.ghcr_token
  container_image      = var.backend_container_image
  service_type         = "backend"
  valkey_password      = var.redis_password
  network_id           = tostring(module.hetzner_network_eu.network_id)

  renderer_container_image = var.renderer_container_image

  deploy_script_content = file("${path.module}/../../../backend/.github/scripts/deploy-hetzner.sh")
  traefik_host          = var.traefik_host
  acme_email            = var.acme_email
  renderer_container_env_vars = {
    API_URL               = "https://api.paymentform.io"
    DOMAIN                = "paymentform.io"
    KV_STORE_BASE_URL     = "https://paymentform-tenant-validator-prod.bitapps.workers.dev"
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    STRIPE_KEY            = var.stripe_public_key
    RESERVED_SUBDOMAINS   = "www, api, admin, app, mail, ftp, smtp, imap, pop,dns, cdn, static, assets, blog, docs, help, support,status, test, staging, dev, development, develop, developer,localhost, email, webmail, calendar, files, git, svn, chat,wiki, forum, shop, store, auth, metrics, monitoring"
    NODE_ENV              = "production"
  }
  backend_container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    APP_DOMAIN        = "api.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = "12"

    LOG_CHANNEL              = "status_worker"
    LOG_DEPRECATIONS_CHANNEL = ""
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.postgres_database.primary_endpoint
    DB_PORT       = "5432"
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"
    TENANT_DB_AUTH_TOKEN        = var.tenant_db_auth_token

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = "10080"
    SESSION_ENCRYPT  = "false"
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = ""

    BROADCAST_CONNECTION = "reverb"
    FILESYSTEM_DISK      = "local"
    # Hetzner has no AWS instance-role path to SQS. Keep redis until either
    # a dedicated IAM user is provisioned (SQS_KEY/SQS_SECRET) or Hetzner
    # routes queues to a non-AWS broker.
    QUEUE_CONNECTION = "redis"
    CACHE_STORE      = "redis"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = "10.1.0.10"
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.upload_storage_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.upload_storage_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = "paymentform-uploads-us"
    AWS_BUCKET_EU               = "paymentform-uploads-eu"
    AWS_BUCKET_AP               = "paymentform-uploads-ap"
    AWS_USE_PATH_STYLE_ENDPOINT = "true"
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_ENDPOINT_EU             = "https://${var.cloudflare_account_id}.eu.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CDN_URL                 = "https://cdn-us.paymentform.io"
    AWS_CDN_URL_EU              = "https://cdn-eu.paymentform.io"
    AWS_CDN_URL_AP              = "https://cdn-ap.paymentform.io"
    AWS_ACCESS_KEY_ID_EU        = var.upload_storage_access_key_id_eu
    AWS_SECRET_ACCESS_KEY_EU    = var.upload_storage_secret_access_key_eu
    AWS_ACCESS_KEY_ID_AP        = var.upload_storage_access_key_id_ap
    AWS_SECRET_ACCESS_KEY_AP    = var.upload_storage_secret_access_key_ap

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST,GET,OPTIONS,PUT,DELETE,PATCH"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant,X-Embed"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    # Sanctum matches this via Str::is — patterns are globs, not cookie-domain
    # syntax. Leading dot here matches NOTHING (e.g. ".paymentform.io/*" does
    # not match "app.paymentform.io/"). Must be an explicit host list. The
    # leading-dot cookie-scope semantics belong on SESSION_DOMAIN only.
    SANCTUM_STATEFUL_DOMAINS = "paymentform.io,app.paymentform.io,api.paymentform.io"

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

    REVERB_APP_ID          = "1e1593236fab"
    REVERB_APP_KEY         = var.reverb_app_key
    REVERB_APP_SECRET      = var.reverb_app_secret
    REVERB_HOST            = "0.0.0.0"
    REVERB_PORT            = "8080"
    REVERB_SCHEME          = "http"
    REVERB_SCALING_ENABLED = "false"
    # activity_timeout 30s (default) is too aggressive — connections silently drop after the
    # client's pong cycle exceeds 30s under load. 120s gives breathing room without leaking
    # stale connections.
    REVERB_APP_PING_INTERVAL    = "60"
    REVERB_APP_ACTIVITY_TIMEOUT = "120"


  }
  caddy_env_vars = {
    ACME_EMAIL                       = "hello@paymentform.io"
    APP_DOMAIN                       = "api-eu.paymentform.io"
    DOMAIN                           = "paymentform.io"
    CADDY_LOG_LEVEL                  = "debug"
    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
    KV_STORE_API_URL                 = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_API_TOKEN               = var.kv_store_api_token
  }

  standard_tags = local.standard_tags
}

module "hetzner_db_hel1" {
  source = "../../providers/hetzner/database"

  environment           = "prod"
  resource_prefix       = "paymentform-p-eu"
  region                = "eu-hel1"
  location              = "hel1"
  server_type           = "cpx22"
  server_image          = "ubuntu-24.04"
  ssh_key_id            = local.hetzner_ssh_key_id
  os_user_public_key    = var.hetzner_ssh_public_key
  ssh_private_key_path  = var.hetzner_ssh_private_key_path
  admin_cidr_blocks     = var.admin_cidr_blocks
  backend_private_cidrs = []
  volume_size_gb        = 30
  backend_public_ipv4   = module.hetzner_backend_hel1.ipv4_address
  primary_host          = module.tunnel_db.tunnel_cname
  db_password           = var.db_password
  network_id            = tostring(module.hetzner_network_eu.network_id)
  standard_tags         = local.standard_tags
  enabled               = false
}

module "hetzner_backend_sin1" {
  source = "../../providers/hetzner/server"

  enabled              = false
  environment          = "prod"
  resource_prefix      = "paymentform-p-sg"
  region               = "ap-sin1"
  location             = "sin"
  server_type          = "cpx22"
  server_image         = "ubuntu-24.04"
  ssh_key_id           = local.hetzner_ssh_key_id
  os_user_public_key   = var.hetzner_ssh_public_key
  ssh_private_key_path = var.hetzner_ssh_private_key_path
  admin_cidr_blocks    = var.admin_cidr_blocks
  ghcr_username        = var.ghcr_username
  ghcr_token           = var.ghcr_token
  container_image      = var.backend_container_image
  service_type         = "backend"
  valkey_password      = var.redis_password
  network_id           = tostring(module.hetzner_network_ap.network_id)

  renderer_container_image = var.renderer_container_image

  deploy_script_content = file("${path.module}/../../../backend/.github/scripts/deploy-hetzner.sh")
  traefik_host          = var.traefik_host
  acme_email            = var.acme_email

  renderer_container_env_vars = {
    API_URL               = "https://api.paymentform.io"
    DOMAIN                = "paymentform.io"
    KV_STORE_BASE_URL     = "https://paymentform-tenant-validator-prod.bitapps.workers.dev"
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    STRIPE_KEY            = var.stripe_public_key
    RESERVED_SUBDOMAINS   = "www, api, admin, app, mail, ftp, smtp, imap, pop,dns, cdn, static, assets, blog, docs, help, support,status, test, staging, dev, development, develop, developer,localhost, email, webmail, calendar, files, git, svn, chat,wiki, forum, shop, store, auth, metrics, monitoring"
    NODE_ENV              = "production"
  }
  backend_container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    APP_DOMAIN        = "api.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = "12"

    LOG_CHANNEL              = "status_worker"
    LOG_DEPRECATIONS_CHANNEL = ""
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.postgres_database.primary_endpoint
    DB_PORT       = "5432"
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"
    TENANT_DB_AUTH_TOKEN        = var.tenant_db_auth_token

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = "10080"
    SESSION_ENCRYPT  = "false"
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = ""

    BROADCAST_CONNECTION = "reverb"
    FILESYSTEM_DISK      = "local"
    # Hetzner has no AWS instance-role path to SQS. Keep redis until either
    # a dedicated IAM user is provisioned (SQS_KEY/SQS_SECRET) or Hetzner
    # routes queues to a non-AWS broker.
    QUEUE_CONNECTION = "redis"
    CACHE_STORE      = "redis"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = "10.1.0.10"
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.upload_storage_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.upload_storage_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = "paymentform-uploads-us"
    AWS_BUCKET_EU               = "paymentform-uploads-eu"
    AWS_BUCKET_AP               = "paymentform-uploads-ap"
    AWS_USE_PATH_STYLE_ENDPOINT = "true"
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_ENDPOINT_EU             = "https://${var.cloudflare_account_id}.eu.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CDN_URL                 = "https://cdn-us.paymentform.io"
    AWS_CDN_URL_EU              = "https://cdn-eu.paymentform.io"
    AWS_CDN_URL_AP              = "https://cdn-ap.paymentform.io"
    AWS_ACCESS_KEY_ID_EU        = var.upload_storage_access_key_id_eu
    AWS_SECRET_ACCESS_KEY_EU    = var.upload_storage_secret_access_key_eu
    AWS_ACCESS_KEY_ID_AP        = var.upload_storage_access_key_id_ap
    AWS_SECRET_ACCESS_KEY_AP    = var.upload_storage_secret_access_key_ap

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST,GET,OPTIONS,PUT,DELETE,PATCH"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant,X-Embed"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    # Sanctum matches this via Str::is — patterns are globs, not cookie-domain
    # syntax. Leading dot here matches NOTHING (e.g. ".paymentform.io/*" does
    # not match "app.paymentform.io/"). Must be an explicit host list. The
    # leading-dot cookie-scope semantics belong on SESSION_DOMAIN only.
    SANCTUM_STATEFUL_DOMAINS = "paymentform.io,app.paymentform.io,api.paymentform.io"

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

    REVERB_APP_ID          = "1e1593236fab"
    REVERB_APP_KEY         = var.reverb_app_key
    REVERB_APP_SECRET      = var.reverb_app_secret
    REVERB_HOST            = "0.0.0.0"
    REVERB_PORT            = "8080"
    REVERB_SCHEME          = "http"
    REVERB_SCALING_ENABLED = "false"
    # activity_timeout 30s (default) is too aggressive — connections silently drop after the
    # client's pong cycle exceeds 30s under load. 120s gives breathing room without leaking
    # stale connections.
    REVERB_APP_PING_INTERVAL    = "60"
    REVERB_APP_ACTIVITY_TIMEOUT = "120"


  }
  caddy_env_vars = {
    ACME_EMAIL                       = "hello@paymentform.io"
    APP_DOMAIN                       = "api-ap.paymentform.io"
    DOMAIN                           = "paymentform.io"
    CADDY_LOG_LEVEL                  = "debug"
    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
    KV_STORE_API_URL                 = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_API_TOKEN               = var.kv_store_api_token
  }

  standard_tags = local.standard_tags
}

module "hetzner_db_sin1" {
  source = "../../providers/hetzner/database"

  environment           = "prod"
  resource_prefix       = "paymentform-p-sg"
  region                = "ap-sin1"
  location              = "sin"
  server_type           = "cpx12"
  server_image          = "ubuntu-24.04"
  ssh_key_id            = local.hetzner_ssh_key_id
  os_user_public_key    = var.hetzner_ssh_public_key
  ssh_private_key_path  = var.hetzner_ssh_private_key_path
  admin_cidr_blocks     = var.admin_cidr_blocks
  backend_private_cidrs = []
  backend_public_ipv4   = module.hetzner_backend_sin1.ipv4_address
  volume_size_gb        = 30
  primary_host          = module.tunnel_db.tunnel_cname
  db_password           = var.db_password
  network_id            = tostring(module.hetzner_network_ap.network_id)
  standard_tags         = local.standard_tags
  enabled               = false
}

module "paymenform_dns" {
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

  api_cname                   = module.paymentform_alb_backend.alb_dns_name
  app_origin_ips              = []
  renderer_container_endpoint = module.paymentform_nlb_renderer.nlb_dns_name

  enable_geo_routing = false
  region_endpoints   = {}
  region_hostnames   = {}

  cloudflare_plan      = "free"
  enable_load_balancer = false
  enable_waf           = false
  enable_rate_limiting = false
  rate_limit_requests  = 100
  health_check_path    = "/health"
  notification_email   = ""
}

# =============================================================================
# Status Page (Cloudflare Worker)
# =============================================================================
module "paymentform_status" {
  source = "../../providers/cloudflare/status"

  environment             = "prod"
  resource_prefix         = local.resource_prefix
  standard_tags           = local.standard_tags
  cloudflare_account_id   = var.cloudflare_account_id
  cloudflare_api_token    = var.cloudflare_api_token
  cloudflare_zone_id      = var.cloudflare_zone_id
  domain_name             = "paymentform.io"
  status_subdomain        = "status"
  status_admin_token      = var.status_admin_token
  log_ingest_token        = var.status_log_ingest_token
  admin_allowed_countries = var.status_admin_allowed_countries
  admin_allowed_ips       = var.status_admin_allowed_ips

  services = [
    {
      name       = "API (Backend)"
      health_url = "https://api.paymentform.io/up"
    },
    {
      name       = "Renderer"
      health_url = "https://renderer.paymentform.io/health"
    },
    {
      name       = "Client"
      health_url = "https://app.paymentform.io"
    },
  ]
}
