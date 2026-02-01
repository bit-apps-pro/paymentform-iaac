environment        = "prod"
region             = "us-east-1"
domain_name        = "paymentform.io"
allow_origin_hosts = "renderer.paymentform.io,*.renderer.paymentform.io"

# Neon database configuration (serverless PostgreSQL)
# Neon API key provided via TF_VAR_neon_api_key environment variable

# Turso database configuration (tenant databases)
# Turso API token provided via TF_VAR_turso_api_token environment variable

# Production environment sizing - Graviton instances for better price/performance
backend_instance_type  = "c7g.large"
client_instance_type   = "c7g.large"
renderer_instance_type = "c7g.large"

# Databases automatically provide:
# - High availability with read replicas
# - Point-in-time recovery
# - Automatic backups
# - Connection pooling
# - Encryption at rest and in transit

# Enhanced monitoring and logging
enable_enhanced_monitoring = true
log_retention_days         = 30
enable_detailed_logging    = true
