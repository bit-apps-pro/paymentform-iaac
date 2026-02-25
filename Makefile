# Root-level Makefile for OpenTofu operations
# Run any tofu command from root iaac/ directory

.PHONY: help init plan apply destroy validate fmt lint security-scan clean \
	localstack-start localstack-stop localstack-test \
	cost-estimate cost-estimate-all \
	security-checkov security-tfsec security-full \
	test-complete test-local test-security test-costs \
	install-tools

ENV ?= dev
REGION ?= us-east-1
AWS_PROFILE ?= default

# Export so all aws CLI calls and OpenTofu (which uses the same credential chain) use this profile
export AWS_PROFILE

# Fetch credentials from AWS Secrets Manager
fetch-credentials:
	@echo "Fetching database credentials..."
	@export TF_VAR_neon_api_key=$$(aws secretsmanager get-secret-value \
		--secret-id neon-api-key \
		--query SecretString \
		--output text 2>/dev/null || echo "$$TF_VAR_neon_api_key"); \
	export TF_VAR_turso_api_token=$$(aws secretsmanager get-secret-value \
		--secret-id turso-api-token \
		--query SecretString \
		--output text 2>/dev/null || echo "$$TF_VAR_turso_api_token"); \
	if [ -z "$$TF_VAR_neon_api_key" ] || [ -z "$$TF_VAR_turso_api_token" ]; then \
		echo "⚠️  Set database credentials:"; \
		echo "   aws secretsmanager create-secret --name neon-api-key --secret-string 'your-key'"; \
		echo "   aws secretsmanager create-secret --name turso-api-token --secret-string 'your-token'"; \
	fi

help:
	@echo "OpenTofu Infrastructure Management"
	@echo "==================================="
	@echo ""
	@echo "Usage: make [target] ENV=<env> REGION=<region>"
	@echo ""
	@echo "Environments: dev, sandbox, prod (default: dev)"
	@echo "Region: AWS region (default: us-east-1)"
	@echo ""
	@echo "Core Targets:"
	@echo "  init          - Initialize OpenTofu working directory"
	@echo "  plan          - Generate and show execution plan"
	@echo "  apply         - Apply the changes"
	@echo "  destroy       - Destroy infrastructure"
	@echo "  validate      - Validate configuration syntax"
	@echo "  fmt           - Format all .tf files"
	@echo "  lint          - Run security and quality checks"
	@echo "  clean         - Remove .terraform directory"

	@echo "Local Build & Deploy (Cost Optimized):"
	@echo "  dev-build         - Build images locally for dev ($0)"
	@echo "  dev-up            - Start dev environment with local images"
	@echo "  dev-local         - Build + start dev in one command"
	@echo "  build-local       - Build for sandbox/prod"
	@echo "  ecr-login         - Authenticate with AWS ECR"
	@echo "  push-to-ecr       - Push images to ECR (~$1-5/month)"
	@echo "  local-deploy      - Full workflow: build → ECR → deploy"
	@echo ""
	@echo "LocalStack Testing:"
	@echo "  localstack-start  - Start LocalStack container"
	@echo "  localstack-stop   - Stop LocalStack container"
	@echo "  localstack-test   - Full LocalStack test cycle"
	@echo ""
	@echo "Security Scanning:"
	@echo "  security-checkov  - Run Checkov scanner"
	@echo "  security-tfsec    - Run Tfsec scanner"
	@echo "  security-full     - Run both scanners"
	@echo ""
	@echo "Cost Estimation:"
	@echo "  cost-estimate     - Estimate costs for ENV"
	@echo "  cost-estimate-all - Estimate all environments"
	@echo ""
	@echo "Integration Testing:"
	@echo "  test-local        - Test with LocalStack"
	@echo "  test-security     - Run security scans"
	@echo "  test-costs        - Estimate all costs"
	@echo "  test-complete     - Run all tests"
	@echo ""
	@echo "Setup:"
	@echo "  install-tools     - Install testing tools"
	@echo ""
	@echo "Examples:"
	@echo "  make install-tools"
	@echo "  make init ENV=dev"
	@echo "  make plan ENV=sandbox"
	@echo "  make apply ENV=prod"
	@echo "  make localstack-start"
	@echo "  make cost-estimate ENV=dev"
	@echo "  make security-full"
	@echo "  make test-complete"

init:
	@echo "Initializing OpenTofu for $(ENV) environment..."
	@tofu init -backend-config=infrastructure/environments/$(ENV)/backend.hcl

plan:
	@echo "Planning changes for $(ENV) environment..."
	@tofu plan -var-file=infrastructure/environments/$(ENV)/terraform.tfvars -out=tfplan-$(ENV)

apply:
	@echo "Applying changes for $(ENV) environment..."
	@if [ -f tfplan-$(ENV) ]; then \
		tofu apply tfplan-$(ENV); \
	else \
		echo "Plan file not found. Run 'make plan ENV=$(ENV)' first."; \
	fi

destroy:
	@echo "WARNING: Destroying infrastructure for $(ENV) environment"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	@export TF_VAR_neon_api_key=$$(aws secretsmanager get-secret-value --secret-id neon-api-key --query SecretString --output text 2>/dev/null || echo "$$TF_VAR_neon_api_key"); \
	export TF_VAR_turso_api_token=$$(aws secretsmanager get-secret-value --secret-id turso-api-token --query SecretString --output text 2>/dev/null || echo "$$TF_VAR_turso_api_token"); \
	tofu destroy -var-file=infrastructure/environments/$(ENV)/terraform.tfvars

validate:
	@echo "Validating OpenTofu configuration..."
	@tofu validate

fmt:
	@echo "Formatting all .tf files..."
	@tofu fmt -recursive .

lint: validate fmt
	@echo "Configuration validated and formatted"

security-scan:
	@echo "Running Checkov security scan..."
	@checkov -d . --framework terraform --check CKV_AWS_

tfsec-scan:
	@echo "Running tfsec security scan..."
	@tfsec .

clean:
	@echo "Cleaning up .terraform directories..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete
	@echo "Cleanup complete"

output:
	@echo "Outputs for $(ENV) environment:"
	@tofu output -var-file=infrastructure/environments/$(ENV)/terraform.tfvars

state-list:
	@echo "Resources in state:"
	@tofu state list

state-show:
	@tofu state show

refresh:
	@echo "Refreshing state for $(ENV)..."
	@tofu refresh -var-file=infrastructure/environments/$(ENV)/terraform.tfvars

# Convenience targets for each environment
dev: ENV=dev
dev: plan

sandbox: ENV=sandbox
sandbox: plan

prod: ENV=prod
prod: plan

# Quick setup
quick-start: validate
	@echo "Quick start - all validations passed!"
	@echo "Next steps:"
	@echo "  1. make init ENV=dev"
	@echo "  2. make plan ENV=dev"
	@echo "  3. make apply ENV=dev"

# ============================================
# LocalStack Testing Targets
# ============================================

localstack-start:
	@echo "🚀 Starting LocalStack..."
	@docker-compose -f local/localstack.yml up -d
	@echo "⏳ Waiting for LocalStack to be ready..."
	@sleep 5
	@echo "✓ LocalStack running at http://localhost:4566"
	@curl -s http://localhost:4566/_localstack/health | jq . 2>/dev/null || echo "Health check in progress..."

localstack-stop:
	@echo "🛑 Stopping LocalStack..."
	@docker-compose -f local/localstack.yml down
	@echo "✓ LocalStack stopped"

localstack-test: localstack-start
	@echo "🧪 Testing infrastructure with LocalStack..."
	@export AWS_ACCESS_KEY_ID=test && \
	export AWS_SECRET_ACCESS_KEY=test && \
	export AWS_DEFAULT_REGION=us-east-1 && \
	echo "📦 Initializing OpenTofu..." && \
	tofu init -backend-config="endpoint=http://localhost:4566" -backend-config="bucket=tofu-state" -backend-config="key=dev/terraform.tfstate" && \
	echo "📋 Planning deployment..." && \
	tofu plan -var-file=infrastructure/environments/dev/terraform.tfvars -out=tfplan-local && \
	echo "🚀 Applying to LocalStack..." && \
	tofu apply tfplan-local && \
	echo "📊 Outputs:" && \
	tofu output && \
	echo "🧹 Cleaning up..." && \
	tofu destroy -var-file=infrastructure/environments/dev/terraform.tfvars -auto-approve && \
	rm -f tfplan-local
	@make localstack-stop
	@echo "✓ LocalStack test complete"

# ============================================
# Security Scanning Targets
# ============================================

security-checkov:
	@echo "🔒 Running Checkov security scan..."
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d infrastructure/ --framework terraform --output json > security-checkov-report.json; \
		checkov -d infrastructure/ --framework terraform --output cli; \
		echo ""; \
		echo "📄 Full report saved to: security-checkov-report.json"; \
	else \
		echo "❌ Checkov not installed. Install with: pip install checkov"; \
	fi

security-tfsec:
	@echo "🔍 Running Tfsec security scan..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec infrastructure/ --format json > security-tfsec-report.json; \
		tfsec infrastructure/ --format sarif --out security-tfsec-report.sarif; \
		tfsec infrastructure/; \
		echo ""; \
		echo "📄 Full report saved to: security-tfsec-report.json"; \
	else \
		echo "❌ Tfsec not installed. Install with: brew install tfsec"; \
	fi

security-full: security-checkov security-tfsec
	@echo ""; \
	echo "✓ Security scan complete"

# ============================================
# Cost Estimation Targets
# ============================================

cost-estimate:
	@echo "💰 Estimating infrastructure costs for $(ENV)..."
	@if command -v infracost >/dev/null 2>&1; then \
		infracost breakdown --path . \
			--terraform-var-file infrastructure/environments/$(ENV)/terraform.tfvars \
			--format table; \
		infracost breakdown --path . \
			--terraform-var-file infrastructure/environments/$(ENV)/terraform.tfvars \
			--format json > cost-estimate-$(ENV).json; \
		echo ""; \
		echo "📄 JSON report saved to: cost-estimate-$(ENV).json"; \
	else \
		echo "❌ Infracost not installed. Install with: brew install infracost"; \
		echo "📚 Get API key at: https://dashboard.infracost.io"; \
	fi

cost-estimate-all:
	@echo "💰 Estimating costs for all environments..."
	@if command -v infracost >/dev/null 2>&1; then \
		for env in dev sandbox prod; do \
			echo ""; \
			echo "📊 $$env environment:"; \
			infracost breakdown --path . \
				--terraform-var-file infrastructure/environments/$$env/terraform.tfvars \
				--format table; \
			infracost breakdown --path . \
				--terraform-var-file infrastructure/environments/$$env/terraform.tfvars \
				--format json > cost-estimate-$$env.json; \
			echo "  ✓ cost-estimate-$$env.json"; \
		done; \
		echo ""; \
		echo "✓ Cost estimation complete"; \
	else \
		echo "❌ Infracost not installed. Install with: brew install infracost"; \
	fi

# ============================================
# Integrated Testing Targets
# ============================================

test-local: localstack-test
	@echo "✓ Local testing complete"

test-security: security-full
	@echo "✓ Security testing complete"

test-costs: cost-estimate-all
	@echo "✓ Cost analysis complete"

test-complete: validate fmt security-full cost-estimate-all localstack-test
	@echo ""
	@echo "✅ All tests complete!"
	@echo ""
	@echo "📊 Reports generated:"
	@echo "  - security-checkov-report.json"
	@echo "  - security-tfsec-report.json"
	@echo "  - cost-estimate-dev.json"
	@echo "  - cost-estimate-sandbox.json"
	@echo "  - cost-estimate-prod.json"
	@echo ""
	@echo "🚀 Next steps:"
	@echo "  - Review security reports for HIGH severity issues"
	@echo "  - Compare cost estimates across environments"
	@echo "  - Deploy to dev: make init ENV=dev && make plan ENV=dev && make apply ENV=dev"

# ============================================
# Installation Targets
# ============================================

install-tools:
	@echo "🔧 Installing testing tools..."
	@./scripts/install-testing-tools.sh
	@echo ""
	@echo "✓ Installation complete"
	@echo ""
	@echo "Try it out:"
	@echo "  make test-complete"
	@echo "  - Deploy to dev: make init ENV=dev && make plan ENV=dev && make apply ENV=dev"

# Dev local targets
dev-build:       ## Build images locally for dev
	./scripts/build-local-dev.sh

dev-up:          ## Start docker-compose with local images
	docker-compose -f local/docker-compose.dev.yml up -d --build

dev-down:        ## Stop local dev environment
	docker-compose -f local/docker-compose.dev.yml down

dev-local:       ## Build + Up in one command
	./scripts/build-local-dev.sh && docker-compose -f local/docker-compose.dev.yml up -d --build

# Sandbox/Prod targets
build-local:     ## Build for any environment
	@echo "Usage: make build-local ENV=<env>"; ./scripts/build-local.sh $(ENV)

ecr-login:       ## Authenticate with ECR
	@aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(REGION).amazonaws.com || true

push-to-ecr:     ## Push images to ECR
	./scripts/push-to-ecr.sh --tag $(ENV)-$$(date +%Y%m%d%H%M%S) --region $(REGION)

local-deploy:    ## Full workflow: build + push + deploy
	./scripts/deploy-to-env.sh $(ENV)

.DEFAULT_GOAL := help
