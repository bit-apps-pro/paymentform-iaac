# Backend configuration for staging environment state management

bucket         = "paymentform-terraform-state-staging"
key            = "staging/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "paymentform-terraform-lock"
encrypt        = true

# Enable state versioning for recovery
versioning = true

# Require explicit credentials
skip_credentials_validation = false
skip_requesting_account_id  = false
skip_metadata_api_check     = false
skip_region_validation      = false
