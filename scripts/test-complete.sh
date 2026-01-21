#!/bin/bash
# test-complete.sh - Comprehensive testing suite for Payment Form Infrastructure
# Includes: validation, security scanning, cost estimation, and LocalStack testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}[$TESTS_RUN] $1${NC}"
}

print_success() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 not found. Install with: $2"
        return 1
    fi
    return 0
}

# Main testing suite
main() {
    print_section "Payment Form Infrastructure - Complete Testing Suite"
    
    echo "📅 Date: $(date)"
    echo "📍 Location: $(pwd)"
    echo ""
    
    # Check prerequisites
    print_section "Phase 1: Checking Prerequisites"
    
    print_step "Checking Docker availability"
    if check_command "docker" "https://www.docker.com/"; then
        print_success "Docker found: $(docker --version)"
    else
        print_error "Docker is required"
    fi
    
    print_step "Checking Docker Compose availability"
    if check_command "docker-compose" "pip install docker-compose"; then
        print_success "Docker Compose found"
    else
        print_error "Docker Compose is required"
    fi
    
    print_step "Checking OpenTofu availability"
    if check_command "tofu" "https://opentofu.org/"; then
        print_success "OpenTofu found: $(tofu version | head -1)"
    else
        print_error "OpenTofu is required"
    fi
    
    # Code Quality
    print_section "Phase 2: Code Quality & Validation"
    
    print_step "Formatting OpenTofu code"
    if tofu fmt -recursive infrastructure/ > /dev/null 2>&1; then
        print_success "Code formatted"
    else
        print_error "Code formatting failed"
    fi
    
    print_step "Validating OpenTofu syntax"
    if tofu validate > /dev/null 2>&1; then
        print_success "OpenTofu configuration is valid"
    else
        print_error "OpenTofu validation failed"
    fi
    
    # Security Scanning
    print_section "Phase 3: Security Scanning"
    
    # Checkov
    print_step "Running Checkov security scan"
    if command -v checkov &> /dev/null; then
        if checkov -d infrastructure/ --framework terraform --output json > security-checkov-report.json 2>&1; then
            print_success "Checkov scan completed"
            
            # Count issues
            HIGH=$(grep -o '"severity":"high"' security-checkov-report.json | wc -l)
            MEDIUM=$(grep -o '"severity":"medium"' security-checkov-report.json | wc -l)
            LOW=$(grep -o '"severity":"low"' security-checkov-report.json | wc -l)
            
            print_info "Security Issues Found:"
            echo "   - HIGH: $HIGH"
            echo "   - MEDIUM: $MEDIUM"
            echo "   - LOW: $LOW"
            echo "   - Report: security-checkov-report.json"
            
            if [ $HIGH -gt 0 ]; then
                echo ""
                echo -e "${RED}⚠️  WARNING: Found $HIGH HIGH severity issues!${NC}"
                echo "Please review and remediate before deployment."
            fi
        else
            print_error "Checkov scan failed"
        fi
    else
        print_info "Checkov not installed (optional)"
        echo "   Install with: pip install checkov"
    fi
    
    # Tfsec
    print_step "Running Tfsec security scan"
    if command -v tfsec &> /dev/null; then
        if tfsec infrastructure/ --format json > security-tfsec-report.json 2>&1; then
            print_success "Tfsec scan completed"
            
            # Count issues
            TFSEC_ISSUES=$(jq 'length' security-tfsec-report.json 2>/dev/null || echo "0")
            print_info "Issues found: $TFSEC_ISSUES (Report: security-tfsec-report.json)"
        else
            print_error "Tfsec scan failed"
        fi
    else
        print_info "Tfsec not installed (optional)"
        echo "   Install with: brew install tfsec"
    fi
    
    # Cost Estimation
    print_section "Phase 4: Cost Estimation"
    
    if command -v infracost &> /dev/null; then
        for ENV in dev staging prod; do
            print_step "Estimating costs for $ENV environment"
            if [ -d "infrastructure/environments/$ENV" ]; then
                if infracost breakdown --path infrastructure/environments/$ENV/ --format json > cost-estimate-$ENV.json 2>&1; then
                    # Extract total cost
                    TOTAL=$(jq '.totalMonthlyCost' cost-estimate-$ENV.json 2>/dev/null || echo "N/A")
                    print_success "$ENV cost estimate: \$$TOTAL/month (Report: cost-estimate-$ENV.json)"
                else
                    print_error "Cost estimation failed for $ENV"
                fi
            else
                print_info "Environment $ENV not found"
            fi
        done
    else
        print_info "Infracost not installed (optional)"
        echo "   Install with: brew install infracost"
        echo "   Get API key at: https://dashboard.infracost.io"
    fi
    
    # LocalStack Testing
    print_section "Phase 5: LocalStack Integration Testing"
    
    print_step "Checking LocalStack Docker image"
    if docker image inspect localstack/localstack:latest > /dev/null 2>&1; then
        print_success "LocalStack image found"
    else
        print_info "LocalStack image not found locally, will be pulled"
    fi
    
    print_step "Starting LocalStack container"
    if docker-compose -f local/localstack.yml up -d > /dev/null 2>&1; then
        print_success "LocalStack started"
        sleep 5
        
        # Verify LocalStack is healthy
        if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
            print_success "LocalStack health check passed"
            
            print_step "Initializing OpenTofu with LocalStack backend"
            export AWS_ACCESS_KEY_ID=test
            export AWS_SECRET_ACCESS_KEY=test
            export AWS_DEFAULT_REGION=us-east-1
            
            if tofu init \
                -backend-config="endpoint=http://localhost:4566" \
                -backend-config="bucket=tofu-state" \
                -backend-config="key=dev/terraform.tfstate" \
                -backend-config="region=us-east-1" \
                -backend-config="skip_credentials_validation=true" > /dev/null 2>&1; then
                print_success "OpenTofu initialized with LocalStack backend"
                
                print_step "Planning infrastructure deployment"
                if tofu plan -var-file=infrastructure/environments/dev/terraform.tfvars -out=tfplan-local > /dev/null 2>&1; then
                    print_success "Infrastructure plan created"
                    
                    print_step "Applying infrastructure to LocalStack"
                    if tofu apply -auto-approve tfplan-local > /dev/null 2>&1; then
                        print_success "Infrastructure deployed to LocalStack"
                        
                        print_step "Verifying deployed resources"
                        if tofu output > /dev/null 2>&1; then
                            print_success "Resources verified"
                            OUTPUTS=$(tofu output -json 2>/dev/null | jq 'keys | length')
                            print_info "Number of outputs: $OUTPUTS"
                        else
                            print_error "Failed to verify resources"
                        fi
                        
                        print_step "Cleaning up LocalStack resources"
                        if tofu destroy -auto-approve -var-file=infrastructure/environments/dev/terraform.tfvars > /dev/null 2>&1; then
                            print_success "Resources destroyed"
                        else
                            print_error "Failed to destroy resources"
                        fi
                        
                        rm -f tfplan-local
                    else
                        print_error "Failed to apply infrastructure"
                    fi
                else
                    print_error "Failed to plan infrastructure"
                fi
            else
                print_error "Failed to initialize OpenTofu"
            fi
        else
            print_error "LocalStack health check failed"
        fi
        
        print_step "Stopping LocalStack container"
        if docker-compose -f local/localstack.yml down > /dev/null 2>&1; then
            print_success "LocalStack stopped"
        else
            print_error "Failed to stop LocalStack"
        fi
    else
        print_error "Failed to start LocalStack"
    fi
    
    # Summary
    print_section "Test Summary"
    
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        RESULT=0
    else
        echo -e "${RED}❌ Some tests failed. Please review above.${NC}"
        RESULT=1
    fi
    
    echo ""
    echo "📊 Generated Reports:"
    echo "  📄 Security:"
    [ -f security-checkov-report.json ] && echo "    ✓ security-checkov-report.json"
    [ -f security-tfsec-report.json ] && echo "    ✓ security-tfsec-report.json"
    echo "  💰 Cost Estimates:"
    [ -f cost-estimate-dev.json ] && echo "    ✓ cost-estimate-dev.json"
    [ -f cost-estimate-staging.json ] && echo "    ✓ cost-estimate-staging.json"
    [ -f cost-estimate-prod.json ] && echo "    ✓ cost-estimate-prod.json"
    
    echo ""
    echo "🚀 Next Steps:"
    echo "  1. Review security reports (if any HIGH issues found)"
    echo "  2. Review cost estimates across environments"
    echo "  3. Deploy to dev: make init ENV=dev && make plan ENV=dev && make apply ENV=dev"
    echo "  4. Run production tests: make test-complete ENV=prod"
    
    echo ""
    print_section "Testing Suite Complete"
    
    return $RESULT
}

# Run main function
main "$@"
exit $?
