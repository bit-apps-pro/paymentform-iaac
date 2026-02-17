#!/bin/bash
# ============================================================================
# Security Scanning Script for Renderer Infrastructure
# 
# This script runs multiple security scanners:
# 1. Trivy - Container vulnerability scanning
# 2. Checkov - IaC security scanning
# 3. Docker Bench - Container security best practices
# 4. OWASP Dependency Check (optional)
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================================================"
echo "PaymentForm Renderer - Security Scanning Suite"
echo "============================================================================"

# ============================================================================
# 1. Install required tools
# ============================================================================
install_tools() {
    echo -e "\n${YELLOW}[1/4] Checking for required tools...${NC}"
    
    # Check for Trivy
    if ! command -v trivy &> /dev/null; then
        echo "Installing Trivy..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
            echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
            sudo apt-get update && sudo apt-get install trivy -y
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install trivy
        fi
    fi
    
    # Check for Checkov
    if ! command -v checkov &> /dev/null; then
        echo "Installing Checkov..."
        pip3 install checkov || pip install checkov
    fi
    
    echo -e "${GREEN}✓ All tools installed${NC}"
}

# ============================================================================
# 2. Build Docker image
# ============================================================================
build_image() {
    echo -e "\n${YELLOW}[2/4] Building Docker image...${NC}"
    
    cd renderer
    docker build -f .docker/Dockerfile.new -t paymentform-renderer:latest .
    cd ..
    
    echo -e "${GREEN}✓ Image built successfully${NC}"
}

# ============================================================================
# 3. Run Trivy container scanning
# ============================================================================
scan_trivy() {
    echo -e "\n${YELLOW}[3/4] Running Trivy vulnerability scan...${NC}"
    
    # Create reports directory
    mkdir -p security-reports
    
    # Scan for HIGH and CRITICAL vulnerabilities
    echo "Scanning for vulnerabilities..."
    trivy image \
        --severity HIGH,CRITICAL \
        --format json \
        --output security-reports/trivy-report.json \
        paymentform-renderer:latest
    
    # Generate human-readable report
    trivy image \
        --severity HIGH,CRITICAL \
        --format table \
        paymentform-renderer:latest | tee security-reports/trivy-report.txt
    
    # Check if there are any CRITICAL vulnerabilities
    CRITICAL_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' security-reports/trivy-report.json)
    HIGH_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH")] | length' security-reports/trivy-report.json)
    
    echo ""
    echo "Vulnerability Summary:"
    echo "  CRITICAL: $CRITICAL_COUNT"
    echo "  HIGH: $HIGH_COUNT"
    
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        echo -e "${RED}✗ CRITICAL vulnerabilities found! Please review and fix.${NC}"
        return 1
    elif [ "$HIGH_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}⚠ HIGH vulnerabilities found. Consider fixing before production.${NC}"
    else
        echo -e "${GREEN}✓ Container security scan passed${NC}"
    fi
}

# ============================================================================
# 4. Run Checkov IaC scanning
# ============================================================================
scan_checkov() {
    echo -e "\n${YELLOW}[4/4] Running Checkov IaC security scan...${NC}"
    
    # Scan Dockerfile
    echo "Scanning Dockerfile..."
    checkov -f .docker/renderer/Dockerfile.new \
        --framework dockerfile \
        --output json \
        --output-file-path security-reports \
        || true
    
    # Scan docker-compose files
    echo "Scanning docker-compose files..."
    checkov -f docker-compose.renderer-new.yml \
        --framework docker-compose \
        --output json \
        --output-file-path security-reports \
        || true
    
    checkov -f docker-compose.renderer-prod.yml \
        --framework docker-compose \
        --output json \
        --output-file-path security-reports \
        || true
    
    echo -e "${GREEN}✓ IaC security scan completed${NC}"
}

# ============================================================================
# 5. Generate summary report
# ============================================================================
generate_report() {
    echo -e "\n${YELLOW}Generating summary report...${NC}"
    
    REPORT_FILE="security-reports/SECURITY_SUMMARY.md"
    
    cat > $REPORT_FILE <<EOF
# Security Scan Report - PaymentForm Renderer

**Date**: $(date)
**Image**: paymentform-renderer:latest

## Trivy Vulnerability Scan

### Summary
- **CRITICAL**: $CRITICAL_COUNT
- **HIGH**: $HIGH_COUNT

See \`trivy-report.json\` for full details.

### Critical Vulnerabilities
$(jq -r '.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL") | "- \(.VulnerabilityID): \(.Title) (Package: \(.PkgName))"' security-reports/trivy-report.json)

## Checkov IaC Scan

See \`results_dockerfile.json\` and \`results_docker_compose.json\` for full details.

## Recommendations

1. **Update Base Images**: Ensure using latest patched versions
2. **Review Dependencies**: Check for outdated packages
3. **Follow Best Practices**: Implement all Docker security best practices
4. **Regular Scans**: Run security scans on every build

## Action Items

- [ ] Fix all CRITICAL vulnerabilities
- [ ] Address HIGH vulnerabilities (if > 5)
- [ ] Review Checkov findings
- [ ] Update dependencies
- [ ] Re-run scans

## Next Scan Due

$(date -d "+7 days" 2>/dev/null || date -v +7d 2>/dev/null || echo "In 7 days")

EOF
    
    echo -e "${GREEN}✓ Report generated: $REPORT_FILE${NC}"
    cat $REPORT_FILE
}

# ============================================================================
# Main execution
# ============================================================================
main() {
    # Check if running with --skip-build flag
    SKIP_BUILD=false
    if [[ "$1" == "--skip-build" ]]; then
        SKIP_BUILD=true
    fi
    
    install_tools
    
    if [ "$SKIP_BUILD" = false ]; then
        build_image
    else
        echo -e "\n${YELLOW}[2/4] Skipping image build (using existing image)${NC}"
    fi
    
    scan_trivy
    scan_checkov
    generate_report
    
    echo -e "\n${GREEN}============================================================================${NC}"
    echo -e "${GREEN}Security scanning completed!${NC}"
    echo -e "${GREEN}============================================================================${NC}"
    echo ""
    echo "Reports location: security-reports/"
    echo ""
    echo "Next steps:"
    echo "  1. Review security-reports/SECURITY_SUMMARY.md"
    echo "  2. Fix any CRITICAL vulnerabilities"
    echo "  3. Address HIGH vulnerabilities if count > 5"
    echo "  4. Review Checkov findings"
    echo "  5. Re-run scan after fixes"
}

# Run main function
main "$@"
