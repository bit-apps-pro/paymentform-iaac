#!/bin/bash
# install-testing-tools.sh - Install all required testing tools

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo "  ℹ $1"
}

check_and_install() {
    local tool=$1
    local install_cmd=$2
    local verify_cmd=$3
    local description=$4
    
    echo "Installing $description..."
    
    if command -v $tool &> /dev/null; then
        print_success "$description already installed"
        return 0
    fi
    
    echo "  Running: $install_cmd"
    if eval "$install_cmd"; then
        if command -v $tool &> /dev/null; then
            print_success "$description installed successfully"
            if [ -n "$verify_cmd" ]; then
                eval "$verify_cmd"
            fi
            return 0
        fi
    fi
    
    print_error "Failed to install $description"
    print_info "Please install manually: $install_cmd"
    return 1
}

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

main() {
    print_header "Infrastructure Testing Tools Installation"
    
    OS=$(detect_os)
    echo "Detected OS: $OS"
    echo ""
    
    # Prerequisites
    print_header "Checking Prerequisites"
    
    # Docker
    if command -v docker &> /dev/null; then
        print_success "Docker installed: $(docker --version)"
    else
        print_error "Docker not found"
        echo "  Install from: https://www.docker.com/"
        exit 1
    fi
    
    # Docker Compose
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose installed"
    else
        print_error "Docker Compose not found"
        echo "  Install with: pip install docker-compose"
        exit 1
    fi
    
    # OpenTofu
    if command -v tofu &> /dev/null; then
        print_success "OpenTofu installed: $(tofu version | head -1)"
    else
        print_error "OpenTofu not found"
        echo "  Install from: https://opentofu.org/docs/intro/install/"
        exit 1
    fi
    
    echo ""
    
    # Optional Tools
    print_header "Installing Optional Testing Tools"
    
    case $OS in
        macos)
            print_info "Using Homebrew for macOS"
            
            # Checkov
            if ! command -v checkov &> /dev/null; then
                echo "Installing Checkov (security scanning)..."
                if pip install checkov &> /dev/null; then
                    print_success "Checkov installed"
                else
                    print_error "Failed to install Checkov"
                fi
            else
                print_success "Checkov already installed"
            fi
            
            # Tfsec
            if ! command -v tfsec &> /dev/null; then
                echo "Installing Tfsec (AWS security)..."
                if brew install tfsec &> /dev/null; then
                    print_success "Tfsec installed"
                else
                    print_error "Failed to install Tfsec"
                    print_info "Install manually: brew install tfsec"
                fi
            else
                print_success "Tfsec already installed: $(tfsec --version)"
            fi
            
            # Infracost
            if ! command -v infracost &> /dev/null; then
                echo "Installing Infracost (cost estimation)..."
                if brew install infracost &> /dev/null; then
                    print_success "Infracost installed"
                else
                    print_error "Failed to install Infracost"
                    print_info "Install manually: brew install infracost"
                fi
            else
                print_success "Infracost already installed: $(infracost --version)"
            fi
            ;;
            
        linux)
            print_info "Using apt for Linux"
            
            # Checkov
            if ! command -v checkov &> /dev/null; then
                echo "Installing Checkov (security scanning)..."
                if pip install checkov &> /dev/null; then
                    print_success "Checkov installed"
                else
                    print_error "Failed to install Checkov"
                fi
            else
                print_success "Checkov already installed"
            fi
            
            # Tfsec
            if ! command -v tfsec &> /dev/null; then
                echo "Installing Tfsec (AWS security)..."
                print_info "Download from: https://github.com/aquasecurity/tfsec/releases"
                print_info "Or install: go install github.com/aquasecurity/tfsec/cmd/tfsec@latest"
            else
                print_success "Tfsec already installed: $(tfsec --version)"
            fi
            
            # Infracost
            if ! command -v infracost &> /dev/null; then
                echo "Installing Infracost (cost estimation)..."
                print_info "Download from: https://www.infracost.io/docs/install/"
                print_info "Or via: curl -s https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | bash"
            else
                print_success "Infracost already installed: $(infracost --version)"
            fi
            ;;
        *)
            print_error "Unknown OS: $OS"
            exit 1
            ;;
    esac
    
    echo ""
    print_header "Setup Infracost (Optional but Recommended)"
    
    if command -v infracost &> /dev/null; then
        if [ -z "$INFRACOST_API_KEY" ]; then
            print_info "Infracost requires API key for cost estimation"
            echo "  1. Visit: https://dashboard.infracost.io"
            echo "  2. Create free account (5M API calls/month)"
            echo "  3. Get API key and set environment variable:"
            echo "     export INFRACOST_API_KEY=<your-key>"
            echo "  4. Or authenticate with:"
            echo "     infracost auth login"
        else
            print_success "INFRACOST_API_KEY is set"
        fi
    fi
    
    echo ""
    print_header "Installation Complete"
    
    echo "Installed tools:"
    echo ""
    
    command -v tofu &> /dev/null && echo "  $(tofu version | head -1)"
    command -v checkov &> /dev/null && echo "  ✓ Checkov"
    command -v tfsec &> /dev/null && echo "  ✓ Tfsec"
    command -v infracost &> /dev/null && echo "  ✓ Infracost"
    
    echo ""
    echo "Testing commands available:"
    echo ""
    echo "  make help               - Show all Makefile targets"
    echo "  make test-complete      - Run all tests"
    echo "  make localstack-test    - Test with LocalStack"
    echo "  make security-full      - Security scans"
    echo "  make cost-estimate-all  - Cost estimation"
    echo ""
    
    echo -e "${GREEN}Ready to test!${NC}"
    echo ""
    echo "Quick start:"
    echo "  1. cd /path/to/iaac"
    echo "  2. make test-complete"
    echo "  3. Review reports (security-*.json, cost-estimate-*.json)"
    echo ""
}

main "$@"
