environment        = "sandbox"
domain_name        = "sandbox.paymentform.io"
db_username        = "admin"
s3_bucket_name     = "paymentform-sandbox-storage"
allow_origin_hosts = "*.sandbox.paymentform.io"

# Subdomain configuration
api_subdomain      = "staging.api.paymentform.io"      # Backend API
app_subdomain      = "staging.app.paymentform.io"      # Client Dashboard
renderer_subdomain = "staging.*.paymentform.io"        # Multi-tenant Renderer (wildcard)

# Cloudflare configuration (set via environment variables or secrets)
# cloudflare_zone_id and cloudflare_api_token should be set externally
enable_cloudflare_lb    = true
enable_cloudflare_waf   = true
enable_rate_limiting    = true
rate_limit_requests     = 100
health_check_path       = "/health"
notification_email      = "ops@paymentform.io"

# Origin IPs will be populated after EC2 instances are created
# api_origin_ips      = ["1.2.3.4", "5.6.7.8"]
# app_origin_ips      = ["1.2.3.4", "5.6.7.8"]
# renderer_origin_ip  = "1.2.3.4"

# Sandbox environment sizing (production-like but cost-optimized)
backend_instance_type  = "t3.small"
client_instance_type   = "t3.small"
renderer_instance_type = "t3.small"
db_instance_type       = "db.t3.small"

# Balance between cost and resilience
backup_retention_days = 14
enable_multi_az       = true
enable_read_replicas  = false

# Enable detailed monitoring
enable_enhanced_monitoring = true
log_retention_days         = 14
