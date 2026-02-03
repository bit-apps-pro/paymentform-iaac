environment        = "sandbox"
region             = "us-east-1"
allow_origin_hosts = "*.sandbox.paymentform.io"
domain_name        = "sandbox.paymentform.io"     # Base domain for environment
api_subdomain      = "api.sandbox.paymentform.io" # Backend API endpoint
app_subdomain      = "app.sandbox.paymentform.io" # Client dashboard
renderer_subdomain = "*.sandbox.paymentform.io"   # Multi-tenant renderer (wildcard)


# Neon database configuration (serverless PostgreSQL)
# Neon API key provided via TF_VAR_neon_api_key environment variable

# Turso database configuration (tenant databases)
# Turso API token provided via TF_VAR_turso_api_token environment variable

# Sandbox environment sizing - Graviton instances
backend_instance_type = "t4g.small"

# Databases provide automatic failover and backups
# Production-like configuration for testing

# Enable detailed monitoring
enable_enhanced_monitoring = true
log_retention_days         = 5
