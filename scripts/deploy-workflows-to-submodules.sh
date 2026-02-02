#!/bin/bash
# Script to deploy GitHub Actions workflows to all submodule repositories
# Usage: ./deploy-workflows-to-submodules.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../docs/github-workflows-for-submodules"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Deploy GitHub Actions Workflows to Submodules          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Error: This script must be run from the repository root${NC}"
    exit 1
fi

# Check if workflows directory exists
if [ ! -d "$WORKFLOWS_DIR" ]; then
    echo -e "${RED}Error: Workflows directory not found at $WORKFLOWS_DIR${NC}"
    exit 1
fi

# Submodules to process
declare -A SUBMODULES=(
    ["backend"]="backend-build.yml"
    ["client"]="client-build.yml"
    ["renderer"]="renderer-build.yml"
    ["admin"]="admin-build.yml"
)

# Function to deploy workflow to a submodule
deploy_workflow() {
    local submodule=$1
    local workflow_file=$2
    
    echo -e "${YELLOW}Processing: ${submodule}${NC}"
    
    # Check if submodule directory exists
    if [ ! -d "$submodule" ]; then
        echo -e "${RED}  ✗ Submodule directory not found: $submodule${NC}"
        return 1
    fi
    
    # Check if workflow file exists
    if [ ! -f "$WORKFLOWS_DIR/$workflow_file" ]; then
        echo -e "${RED}  ✗ Workflow file not found: $workflow_file${NC}"
        return 1
    fi
    
    # Navigate to submodule
    cd "$submodule"
    
    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        echo -e "${RED}  ✗ Not a git repository${NC}"
        cd ..
        return 1
    fi
    
    # Get current branch
    current_branch=$(git branch --show-current)
    echo -e "  Current branch: ${current_branch}"
    
    # Create .github/workflows directory
    mkdir -p .github/workflows
    
    # Copy workflow file
    cp "$WORKFLOWS_DIR/$workflow_file" .github/workflows/build.yml
    echo -e "${GREEN}  ✓ Workflow copied to .github/workflows/build.yml${NC}"
    
    # Check if there are changes
    if git diff --quiet .github/workflows/build.yml 2>/dev/null; then
        echo -e "${BLUE}  ℹ No changes detected (workflow already exists)${NC}"
        cd ..
        return 0
    fi
    
    # Ask user if they want to commit
    echo -e "${YELLOW}  Ready to commit changes. Options:${NC}"
    echo "    1) Commit and push"
    echo "    2) Commit only (no push)"
    echo "    3) Skip (leave changes unstaged)"
    echo ""
    read -p "  Choose option [1-3]: " choice
    
    case $choice in
        1)
            git add .github/workflows/build.yml
            git commit -m "Add GitHub Actions workflow with release triggers"
            echo -e "${GREEN}  ✓ Changes committed${NC}"
            
            git push origin "$current_branch"
            echo -e "${GREEN}  ✓ Changes pushed to origin/$current_branch${NC}"
            ;;
        2)
            git add .github/workflows/build.yml
            git commit -m "Add GitHub Actions workflow with release triggers"
            echo -e "${GREEN}  ✓ Changes committed (not pushed)${NC}"
            echo -e "${YELLOW}  ⚠ Remember to push manually: git push origin $current_branch${NC}"
            ;;
        3)
            echo -e "${BLUE}  ℹ Changes left unstaged${NC}"
            ;;
        *)
            echo -e "${RED}  ✗ Invalid option${NC}"
            cd ..
            return 1
            ;;
    esac
    
    cd ..
    echo ""
    return 0
}

# Main execution
echo "This script will deploy GitHub Actions workflows to each submodule."
echo "You'll be prompted for each submodule to commit and push changes."
echo ""
read -p "Continue? [y/N]: " confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
success_count=0
fail_count=0

# Process each submodule
for submodule in "${!SUBMODULES[@]}"; do
    workflow_file="${SUBMODULES[$submodule]}"
    
    if deploy_workflow "$submodule" "$workflow_file"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
done

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Deployment Summary                                      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Successful: $success_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "${RED}✗ Failed: $fail_count${NC}"
fi
echo ""

if [ $success_count -gt 0 ]; then
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Enable GitHub Actions in each repository:"
    echo "   Settings → Actions → General → Allow all actions"
    echo "   Settings → Actions → General → Read and write permissions"
    echo ""
    echo "2. Test workflows:"
    echo "   Actions tab → Build and Push → Run workflow"
    echo ""
    echo "3. Create first release:"
    echo "   gh release create v0.1.0 --generate-notes"
    echo ""
    echo -e "See ${BLUE}iaac/docs/github-workflows-for-submodules/DEPLOYMENT-GUIDE.md${NC} for details"
fi

exit 0
