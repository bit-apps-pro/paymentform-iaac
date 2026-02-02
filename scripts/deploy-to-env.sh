#!/usr/bin/env bash
set -e

# Smart deploy router
# Usage: ./scripts/deploy-to-env.sh <env> [service]
# env: dev | sandbox | prod

ENV_NAME="$1"
SERVICE_FILTER="$2"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

function info(){ echo -e "${YELLOW}[INFO]${NC} $1"; }
function success(){ echo -e "${GREEN}[OK]${NC} $1"; }
function error(){ echo -e "${RED}[ERROR]${NC} $1"; }

if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
  cat <<EOF
Deploy to an environment.

Usage: $0 <env> [service]
  env: dev | sandbox | prod
EOF
  exit 0
fi

case "${ENV_NAME}" in
  dev)
    info "Building local dev images"
    ./scripts/build-local-dev.sh "${SERVICE_FILTER:-}" 
    info "Starting docker-compose for dev"
    docker-compose -f local/docker-compose.dev.yml up -d --build
    success "Dev environment is up"
    ;;
  sandbox|prod)
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    info "Building images for ${ENV_NAME}"
    ./scripts/build-local.sh "${ENV_NAME}" "${SERVICE_FILTER:-}"
    # use tag pattern produced in build-local: <env>-<timestamp> (we pass timestamp to push)
    TAG="${ENV_NAME}-${TIMESTAMP}"
    info "Pushing images to ECR with tag ${TAG}"
    ./scripts/push-to-ecr.sh --tag "${TAG}" --region "${AWS_DEFAULT_REGION:-us-east-1}" --services "${SERVICE_FILTER:-backend,client,renderer,admin}"

    info "Triggering remote deployment (placeholder)." 
    echo "Implement deployment trigger (e.g., CI/CD, ECS update, k8s rollout)"
    success "Sandbox/Prod workflow complete (images pushed)"
    ;;
  *) error "Unknown environment: ${ENV_NAME}"; exit 1;;
esac

exit 0
