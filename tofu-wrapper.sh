#!/bin/bash

# tofu-wrapper.sh - Convenience wrapper for running OpenTofu from root directory
# Usage: ./tofu-wrapper.sh [command] [env] [additional-args]
#
# Examples:
#   ./tofu-wrapper.sh init dev
#   ./tofu-wrapper.sh plan staging
#   ./tofu-wrapper.sh apply prod
#   ./tofu-wrapper.sh validate
#   ./tofu-wrapper.sh destroy dev
#   ./tofu-wrapper.sh fmt

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
COMMAND="${1:---help}"
ENV="${2:-dev}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="${ROOT_DIR}/infrastructure"

# Functions
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

validate_env() {
    case "$1" in
        dev|staging|prod)
            return 0
            ;;
        *)
            print_error "Invalid environment: $1"
            echo "Valid environments: dev, staging, prod"
            exit 1
            ;;
    esac
}

check_prerequisites() {
    if ! command -v tofu &> /dev/null; then
        print_error "OpenTofu is not installed or not in PATH"
        exit 1
    fi
    print_success "OpenTofu found: $(tofu version | head -1)"
}

run_command() {
    case "$COMMAND" in
        init)
            validate_env "$ENV"
            print_header "Initializing OpenTofu for $ENV environment"
            tofu init -backend-config="$INFRASTRUCTURE_DIR/environments/$ENV/backend.hcl"
            print_success "Initialization complete"
            ;;
        
        plan)
            validate_env "$ENV"
            print_header "Planning changes for $ENV environment"
            tofu plan -var-file="$INFRASTRUCTURE_DIR/environments/$ENV/terraform.tfvars" -out="tfplan-$ENV"
            print_success "Plan generated: tfplan-$ENV"
            ;;
        
        apply)
            validate_env "$ENV"
            print_header "Applying changes for $ENV environment"
            if [ -f "tfplan-$ENV" ]; then
                tofu apply "tfplan-$ENV"
                print_success "Infrastructure applied"
            else
                print_error "Plan file not found: tfplan-$ENV"
                echo "Run './tofu-wrapper.sh plan $ENV' first"
                exit 1
            fi
            ;;
        
        destroy)
            validate_env "$ENV"
            print_warning "DESTROYING infrastructure for $ENV environment"
            echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
            sleep 5
            tofu destroy -var-file="$INFRASTRUCTURE_DIR/environments/$ENV/terraform.tfvars"
            print_success "Infrastructure destroyed"
            ;;
        
        validate)
            print_header "Validating OpenTofu configuration"
            tofu validate
            print_success "Validation successful"
            ;;
        
        fmt)
            print_header "Formatting OpenTofu files"
            tofu fmt -recursive "$INFRASTRUCTURE_DIR"
            print_success "Formatting complete"
            ;;
        
        security-scan)
            print_header "Running Checkov security scan"
            if command -v checkov &> /dev/null; then
                checkov -d "$INFRASTRUCTURE_DIR" --framework terraform --check CKV_AWS_
                print_success "Security scan complete"
            else
                print_error "Checkov is not installed"
                echo "Install it with: pip install checkov"
                exit 1
            fi
            ;;
        
        tfsec)
            print_header "Running tfsec security scan"
            if command -v tfsec &> /dev/null; then
                tfsec "$INFRASTRUCTURE_DIR"
                print_success "tfsec scan complete"
            else
                print_error "tfsec is not installed"
                echo "Install it with: brew install tfsec (macOS) or see https://github.com/aquasecurity/tfsec"
                exit 1
            fi
            ;;
        
        clean)
            print_header "Cleaning up OpenTofu files"
            find "$INFRASTRUCTURE_DIR" -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
            find "$INFRASTRUCTURE_DIR" -name ".terraform.lock.hcl" -delete
            rm -f tfplan-*
            print_success "Cleanup complete"
            ;;
        
        output)
            validate_env "$ENV"
            print_header "Outputs for $ENV environment"
            tofu output -var-file="$INFRASTRUCTURE_DIR/environments/$ENV/terraform.tfvars"
            ;;
        
        state-list)
            print_header "Resources in state"
            tofu state list
            ;;
        
        state-show)
            print_header "State details"
            tofu state show
            ;;
        
        refresh)
            validate_env "$ENV"
            print_header "Refreshing state for $ENV"
            tofu refresh -var-file="$INFRASTRUCTURE_DIR/environments/$ENV/terraform.tfvars"
            print_success "State refreshed"
            ;;
        
        help|--help|-h)
            print_header "OpenTofu Wrapper - Command Reference"
            cat << EOF
Usage: $0 [command] [env] [additional-args]

Commands:
  init              Initialize OpenTofu working directory
  plan              Generate and show execution plan
  apply             Apply the changes
  destroy           Destroy infrastructure
  validate          Validate configuration syntax
  fmt               Format all .tf files
  security-scan     Run Checkov security scan
  tfsec             Run tfsec security scan
  clean             Remove temporary files
  output            Show outputs
  state-list        List resources in state
  state-show        Show detailed state
  refresh           Refresh state
  help              Show this help message

Environments:
  dev               Development (default)
  staging           Staging/Pre-production
  prod              Production

Examples:
  $0 init dev
  $0 plan staging
  $0 apply prod
  $0 validate
  $0 fmt
  $0 security-scan
  $0 destroy prod

Environment variable:
  Set ENV=staging to use staging by default

EOF
            ;;
        
        *)
            print_error "Unknown command: $COMMAND"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    check_prerequisites
    run_command
}

main "$@"
