# Backend configuration for development environment state management

bucket         = "paymentform-terraform-state-dev"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "paymentform-terraform-lock-dev"
encrypt        = true

# Skip credentials verification for CI/CD
skip_credentials_validation = false

# Skip requesting account ID
skip_requesting_account_id = false

# Skip metadata API check
skip_metadata_api_check = false

# Allow unmatched provider version
skip_region_validation = false
