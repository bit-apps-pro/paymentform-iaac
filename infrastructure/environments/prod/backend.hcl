# Backend configuration for production environment state management
# Enhanced security for production state

bucket         = "paymentform-terraform-state-prod"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "paymentform-terraform-lock"
encrypt        = true

# State versioning for disaster recovery
versioning = true

# Credential validation
skip_credentials_validation = false
skip_requesting_account_id  = false
skip_metadata_api_check     = false
skip_region_validation      = false

# Additional security settings (configured in S3 bucket directly)
# - Versioning enabled
# - MFA delete enabled
# - KMS encryption with separate key
# - Access logging enabled
# - Block public access enabled
# - Compliance mode enabled
