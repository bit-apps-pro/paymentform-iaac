environment        = "staging"
region             = "us-east-1"
domain_name        = "staging.paymentform.io"
allow_origin_hosts = "*.staging.paymentform.io"

# Neon database configuration (serverless PostgreSQL)
# Neon API key provided via TF_VAR_neon_api_key environment variable

# Turso database configuration (tenant databases)
# Turso API token provided via TF_VAR_turso_api_token environment variable

# Staging environment sizing - Graviton instances
backend_instance_type  = "t4g.small"
client_instance_type   = "t4g.small"
renderer_instance_type = "t4g.small"

# Databases provide automatic failover and backups
# Production-like configuration for testing

# Enable detailed monitoring
enable_enhanced_monitoring = true
log_retention_days         = 14
