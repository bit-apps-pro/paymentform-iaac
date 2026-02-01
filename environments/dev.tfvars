environment        = "dev"
region             = "us-east-1"
domain_name        = "dev.paymentform.local"
allow_origin_hosts = "*.dev.paymentform.local"

# Neon database configuration (serverless PostgreSQL)
# Neon API key provided via TF_VAR_neon_api_key environment variable

# Turso database configuration (tenant databases)
# Turso API token provided via TF_VAR_turso_api_token environment variable

# Dev environment sizing - Graviton instances for cost optimization
backend_instance_type  = "t4g.micro"
client_instance_type   = "t4g.micro"
renderer_instance_type = "t4g.micro"

# Databases are serverless, no instance type needed
hxuA6P5UrRk4