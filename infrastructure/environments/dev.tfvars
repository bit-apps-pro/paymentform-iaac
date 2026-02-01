environment        = "dev"
domain_name        = "dev.paymentform.local"
db_username        = "admin"
s3_bucket_name     = "paymentform-dev-storage"
allow_origin_hosts = "*.dev.paymentform.local"

# Subdomain configuration
api_subdomain      = "api.dev.paymentform.local"      # Backend API
app_subdomain      = "app.dev.paymentform.local"      # Client Dashboard
renderer_subdomain = "*.dev.paymentform.local"        # Multi-tenant Renderer (wildcard)

# Dev environment sizing
backend_instance_type  = "t3.micro"
client_instance_type   = "t3.micro"
renderer_instance_type = "t3.micro"
db_instance_type       = "db.t3.micro"

# Cost optimization for dev
backup_retention_days = 7
enable_multi_az       = false
enable_read_replicas  = false
