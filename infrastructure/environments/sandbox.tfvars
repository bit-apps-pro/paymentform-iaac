environment        = "sandbox"
domain_name        = "sandbox.paymentform.io"
db_username        = "admin"
s3_bucket_name     = "paymentform-sandbox-storage"
allow_origin_hosts = "*.sandbox.paymentform.io"

# Subdomain configuration
api_subdomain      = "api.sandbox.paymentform.io"      # Backend API
app_subdomain      = "app.sandbox.paymentform.io"      # Client Dashboard
renderer_subdomain = "*.sandbox.paymentform.io"        # Multi-tenant Renderer (wildcard)

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
