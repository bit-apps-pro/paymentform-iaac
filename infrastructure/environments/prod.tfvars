environment        = "prod"
domain_name        = "paymentform.io"
db_username        = "admin"
s3_bucket_name     = "paymentform-prod-storage"
allow_origin_hosts = "*.paymentform.io"

# Subdomain configuration
api_subdomain      = "api.paymentform.io"      # Backend API
app_subdomain      = "app.paymentform.io"      # Client Dashboard
renderer_subdomain = "*.paymentform.io"        # Multi-tenant Renderer (wildcard)

# Cloudflare configuration (set via environment variables or secrets)
# cloudflare_zone_id and cloudflare_api_token should be set externally
enable_cloudflare_lb    = true
enable_cloudflare_waf   = true
enable_rate_limiting    = true
rate_limit_requests     = 200
health_check_path       = "/health"
notification_email      = "ops@paymentform.io"

# Origin IPs will be populated after EC2 instances are created
# api_origin_ips      = ["1.2.3.4", "5.6.7.8", "9.10.11.12"]
# app_origin_ips      = ["1.2.3.4", "5.6.7.8", "9.10.11.12"]
# renderer_origin_ip  = "1.2.3.4"

# Production environment sizing
backend_instance_type  = "t3.large"
client_instance_type   = "t3.medium"
renderer_instance_type = "t3.large"
db_instance_type       = "db.r6g.large"

# High availability and durability
backup_retention_days      = 30
enable_multi_az            = true
enable_read_replicas       = true
enable_cross_region_backup = true

# Enhanced monitoring and logging
enable_enhanced_monitoring = true
log_retention_days         = 30
enable_detailed_logging    = true

# Security hardening
enable_encryption_at_rest    = true
enable_encryption_in_transit = true
