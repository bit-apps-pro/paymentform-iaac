.PHONY: help init plan apply destroy validate fmt clean output state-list refresh \
	build-local build-local-bases build-local-apps \
	build-libsql-base build-frankenphp-base build-backend-base build-backend \
	build-backend-nginx build-backend-frankenphp \
	build-renderer-base build-renderer build-client build-admin \
	push-to-ecr local-deploy ecr-login \
	cost-estimate \
	security-checkov security-tfsec security-full \
	install-tools quick-start bootstrap bootstrap-full \
	update-backend update-client update-renderer update-admin update-all \
	userdata-generate userdata-sync

ENV_DIR = environments/prod
REGION  ?= us-east-1
AWS_PROFILE ?= default

# Image references. Override IMAGE_TAG for a global tag bump, or override an
# individual <NAME>_IMAGE to point at an entirely different image:
#   make update-client IMAGE_TAG=v1.2.3
#   make update-client CLIENT_IMAGE=ghcr.io/forked/client:abc123
IMAGE_TAG       ?= latest
GHCR_REGISTRY   ?= ghcr.io/bit-apps-pro
BACKEND_IMAGE   ?= $(GHCR_REGISTRY)/paymentform-backend:$(IMAGE_TAG)
CLIENT_IMAGE    ?= $(GHCR_REGISTRY)/paymentform-client:$(IMAGE_TAG)
RENDERER_IMAGE  ?= $(GHCR_REGISTRY)/paymentform-renderer:$(IMAGE_TAG)
ADMIN_IMAGE     ?= $(GHCR_REGISTRY)/paymentform-admin:$(IMAGE_TAG)

export AWS_PROFILE

help:
	@echo "PaymentForm Infrastructure"
	@echo "=========================="
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Core Commands:"
	@echo "  init          Initialize OpenTofu"
	@echo "  plan          Generate execution plan"
	@echo "  apply         Apply changes"
	@echo "  destroy       Destroy infrastructure"
	@echo "  validate      Validate configuration"
	@echo "  fmt           Format .tf files"
	@echo "  clean         Remove .terraform directories"
	@echo "  output        Show outputs"
	@echo "  state-list    List resources in state"
	@echo "  refresh       Refresh state"
	@echo ""
	@echo "Container Image Update (sets the *_container_image tofu var):"
	@echo "  update-client     Update client image    (IMAGE_TAG=x | CLIENT_IMAGE=full)"
	@echo "  update-admin      Update admin image     (IMAGE_TAG=x | ADMIN_IMAGE=full)"
	@echo "  update-backend    Update backend image   (IMAGE_TAG=x | BACKEND_IMAGE=full)"
	@echo "  update-renderer   Update renderer image  (IMAGE_TAG=x | RENDERER_IMAGE=full)"
	@echo "  update-all        Update all four images (IMAGE_TAG=x)"
	@echo "  NOTE: backend/renderer/admin run on VMs; var change rebuilds userdata."
	@echo "        Run 'make userdata-sync PROVIDER=aws|hetzner' to roll instances."
	@echo "        Client runs on Cloudflare Containers — image change deploys directly."
	@echo ""
	@echo "Container Build (local, full chain — uses BUILD_ENV=prod by default):"
	@echo "  build-local              All bases + apps. Prompts for backend variant."
	@echo "  build-local-bases        Only base images for the chosen backend variant"
	@echo "  build-local-apps         All apps (rebuilds bases if missing)"
	@echo "  build-libsql-base        libsql-base only (variant-aware: NTS for nginx, ZTS for frankenphp)"
	@echo "  build-frankenphp-base    Custom xcaddy-built frankenphp binary (variant=frankenphp only)"
	@echo "  build-backend-base       backend-base (libsql + frankenphp built if missing)"
	@echo "  build-backend            backend app for the chosen variant"
	@echo "  build-backend-nginx      Shortcut: build backend on nginx chain"
	@echo "  build-backend-frankenphp Shortcut: build backend on frankenphp chain"
	@echo "  build-renderer-base      renderer-base"
	@echo "  build-renderer           renderer app"
	@echo "  build-client             client app"
	@echo "  build-admin              admin app"
	@echo "  push-to-ecr              Push images to ECR (legacy path; main flow is GHCR)"
	@echo "  local-deploy             Build, push, and deploy"
	@echo "  Override with VARIANT=nginx | VARIANT=frankenphp to skip the picker."
	@echo ""
	@echo "Security Scanning:"
	@echo "  security-checkov  Run Checkov scanner"
	@echo "  security-tfsec    Run Tfsec scanner"
	@echo "  security-full     Run both scanners"
	@echo ""
	@echo "Cost Estimation:"
	@echo "  cost-estimate     Estimate costs"
	@echo ""
	@echo "Toolchain Setup (idempotent — skips installed tools):"
	@echo "  bootstrap         Install core tools: tofu, aws, docker, jq, gh, infracost, checkov, trivy"
	@echo "  bootstrap-full    Core + optional: wrangler, cloudflared, hcloud"
	@echo ""
	@echo "Userdata Management:"
	@echo "  userdata-generate   Render userdata to bash file (PROVIDER=hetzner|aws)"
	@echo "  userdata-sync       Force re-apply userdata (PROVIDER=hetzner|aws)"
	@echo ""
	@echo "Examples:"
	@echo "  make init"
	@echo "  make plan"
	@echo "  make apply"
	@echo "  make update-client IMAGE_TAG=v1.2.3"
	@echo "  make update-all    IMAGE_TAG=v1.2.3"
	@echo "  make update-backend BACKEND_IMAGE=ghcr.io/bit-apps-pro/paymentform-backend@sha256:..."
	@echo "  make userdata-generate PROVIDER=hetzner"
	@echo "  make userdata-sync PROVIDER=aws"

init:
	@cd $(ENV_DIR) && tofu init

plan:
	@cd $(ENV_DIR) && tofu plan -out=tfplan

apply:
	@cd $(ENV_DIR) && tofu apply tfplan

destroy:
	@echo "WARNING: Destroying production infrastructure"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds..."
	@sleep 5
	@cd $(ENV_DIR) && tofu destroy -auto-approve

validate:
	@cd $(ENV_DIR) && tofu validate

fmt:
	@tofu fmt -recursive .

clean:
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete
	@find . -name "tfplan*" -delete

output:
	@cd $(ENV_DIR) && tofu output

state-list:
	@cd $(ENV_DIR) && tofu state list

refresh:
	@cd $(ENV_DIR) && tofu refresh

BUILD_ENV ?= prod
# VARIANT controls the backend chain: nginx (default) or frankenphp.
# Leave it unset to get an interactive picker when running in a terminal.
VARIANT ?=

build-local:
	@VARIANT="$(VARIANT)" ./scripts/build-local.sh $(BUILD_ENV) all

build-local-bases:
	@VARIANT="$(VARIANT)" ./scripts/build-local.sh $(BUILD_ENV) bases

build-local-apps:
	@VARIANT="$(VARIANT)" ./scripts/build-local.sh $(BUILD_ENV) apps

build-libsql-base:
	@VARIANT="$(VARIANT)" ./scripts/build-local.sh $(BUILD_ENV) libsql-base

build-frankenphp-base:
	@VARIANT=frankenphp ./scripts/build-local.sh $(BUILD_ENV) frankenphp-base

build-backend-base:
	@VARIANT="$(VARIANT)" ./scripts/build-local.sh $(BUILD_ENV) backend-base

build-backend:
	@VARIANT="$(VARIANT)" ./scripts/build-local.sh $(BUILD_ENV) backend

# Variant shortcuts (skip the picker).
build-backend-nginx:
	@VARIANT=nginx ./scripts/build-local.sh $(BUILD_ENV) backend

build-backend-frankenphp:
	@VARIANT=frankenphp ./scripts/build-local.sh $(BUILD_ENV) backend

build-renderer-base:
	@./scripts/build-local.sh $(BUILD_ENV) renderer-base

build-renderer:
	@./scripts/build-local.sh $(BUILD_ENV) renderer

build-client:
	@./scripts/build-local.sh $(BUILD_ENV) client

build-admin:
	@./scripts/build-local.sh $(BUILD_ENV) admin

ecr-login:
	@aws ecr get-login-password --region $(REGION) | \
		docker login --username AWS --password-stdin \
		$$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(REGION).amazonaws.com || true

push-to-ecr: ecr-login
	@./scripts/push-to-ecr.sh --env prod --region $(REGION)

local-deploy: build-local push-to-ecr
	@./scripts/deploy-to-env.sh prod

# Scan paths shared across security targets — both iaac roots that hold .tf
# files. --skip-path arguments prune vendored / build dirs that contain
# generated files or fixtures and would slow scans + produce noise.
SECURITY_SCAN_DIRS = providers environments
SECURITY_SKIP_PATHS = .terraform,node_modules,.wrangler,.mf,loadtest,bootstrap,ansible

security-checkov:
	@if ! command -v checkov >/dev/null 2>&1; then \
		echo "Checkov not installed. Install with: pip install checkov"; \
		exit 0; \
	fi; \
	rm -f security-checkov-report.json results_json.json; \
	checkov \
		$(foreach d,$(SECURITY_SCAN_DIRS),-d $(d)) \
		--framework terraform \
		--skip-path $(SECURITY_SKIP_PATHS) \
		--output cli --output json \
		--output-file-path console,security-checkov-report.json \
		--soft-fail; \
	echo "Report: security-checkov-report.json"

# tfsec was archived by Aqua in 2023; trivy is its supported successor and
# bundles the same rules under `trivy config`. Falls back to tfsec only when
# trivy is missing.
security-tfsec:
	@if command -v trivy >/dev/null 2>&1; then \
		trivy config \
			--severity HIGH,CRITICAL \
			--skip-dirs $(SECURITY_SKIP_PATHS) \
			--format json --output security-tfsec-report.json .; \
		trivy config \
			--severity HIGH,CRITICAL \
			--skip-dirs $(SECURITY_SKIP_PATHS) .; \
		echo "Report: security-tfsec-report.json"; \
	elif command -v tfsec >/dev/null 2>&1; then \
		tfsec $(SECURITY_SCAN_DIRS) --format json --out security-tfsec-report.json --soft-fail; \
		tfsec $(SECURITY_SCAN_DIRS) --soft-fail; \
		echo "Report: security-tfsec-report.json"; \
	else \
		echo "Neither trivy nor tfsec installed. Install with one of:"; \
		echo "  brew install trivy           (preferred — tfsec successor)"; \
		echo "  apt install trivy            (debian/ubuntu)"; \
		echo "  brew install tfsec           (legacy, archived)"; \
	fi

security-full: security-checkov security-tfsec

# Run infracost once (network-billable), persist JSON, then render the table
# locally via `infracost output`. Avoids a second cloud-priced scan.
cost-estimate:
	@if ! command -v infracost >/dev/null 2>&1; then \
		echo "Infracost not installed. Install with: brew install infracost"; \
		exit 0; \
	fi; \
	cd $(ENV_DIR) && \
		infracost breakdown --path . --format json --out-file ../../cost-estimate-prod.json && \
		infracost output --path ../../cost-estimate-prod.json --format table && \
		echo "Report: cost-estimate-prod.json"

install-tools:
	@./scripts/install-testing-tools.sh

bootstrap:
	@./scripts/bootstrap.sh

bootstrap-full:
	@./scripts/bootstrap.sh --with-optional

quick-start: validate
	@echo "Validation passed. Next: make init && make plan && make apply"

update-backend:
	@cd $(ENV_DIR) && tofu apply -var="backend_container_image=$(BACKEND_IMAGE)" -auto-approve

update-client:
	@cd $(ENV_DIR) && tofu apply -var="client_container_image=$(CLIENT_IMAGE)" -auto-approve

update-renderer:
	@cd $(ENV_DIR) && tofu apply -var="renderer_container_image=$(RENDERER_IMAGE)" -auto-approve

update-admin:
	@cd $(ENV_DIR) && tofu apply -var="admin_container_image=$(ADMIN_IMAGE)" -auto-approve

update-all:
	@cd $(ENV_DIR) && tofu apply \
		-var="backend_container_image=$(BACKEND_IMAGE)" \
		-var="client_container_image=$(CLIENT_IMAGE)" \
		-var="renderer_container_image=$(RENDERER_IMAGE)" \
		-var="admin_container_image=$(ADMIN_IMAGE)" \
		-auto-approve

# Userdata rendering and management
PROVIDER ?= hetzner

HZ_MODULE ?= module.hetzner_backend_hel1
AWS_MODULE ?= module.paymentform_backend

userdata-generate:
ifeq ($(PROVIDER),hetzner)
	@./scripts/render-userdata.sh hetzner $(HZ_MODULE) hetzner-userdata.sh
else ifeq ($(PROVIDER),aws)
	@./scripts/render-userdata.sh aws $(AWS_MODULE) aws-userdata.sh
else
	@echo "Error: PROVIDER must be 'hetzner' or 'aws'"
	@exit 1
endif

userdata-sync:
ifeq ($(PROVIDER),hetzner)
	@cd $(ENV_DIR) && tofu apply -replace=$(HZ_MODULE).null_resource.ssh_apply_userdata[0]
else ifeq ($(PROVIDER),aws)
	@cd $(ENV_DIR) && tofu apply -replace=$(AWS_MODULE).null_resource.ssm_apply_userdata
else
	@echo "Error: PROVIDER must be 'hetzner' or 'aws'"
	@exit 1
endif

.DEFAULT_GOAL := help
