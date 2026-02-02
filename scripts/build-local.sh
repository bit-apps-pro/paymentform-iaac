#!/usr/bin/env bash
set -e

# Universal local builder for any environment
# Usage: ./scripts/build-local.sh <env> [service]
# Example: ./scripts/build-local.sh sandbox backend

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
Build images for an environment and optionally a single service.

Usage: $0 <env> [service]
  env: dev | sandbox | prod
  service: backend | client | renderer | admin (optional)

Outputs tags like: paymentform-<service>:<env>-<timestamp> and also tags with git SHA
EOF
  exit 0
fi

command -v docker >/dev/null 2>&1 || { error "docker not found"; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
SERVICES=(backend client renderer admin)

if [ -n "${SERVICE_FILTER}" ]; then
  SERVICES=("${SERVICE_FILTER}")
fi

for svc in "${SERVICES[@]}"; do
  BUILD_CTX="${ROOT_DIR}/../${svc}"
  TAG_ENV="${ENV_NAME}-${TIMESTAMP}"
  TAG="paymentform-${svc}:${TAG_ENV}"
  TAG_SHA="paymentform-${svc}:${ENV_NAME}-${GIT_SHA}"

  info "Building ${svc} from ${BUILD_CTX} -> ${TAG}"
  if [ ! -d "${BUILD_CTX}" ]; then
    error "Context directory not found: ${BUILD_CTX}, skipping ${svc}"
    continue
  fi

  docker build --progress=plain -t "${TAG}" "${BUILD_CTX}" || { error "Failed to build ${svc}"; exit 1; }
  docker tag "${TAG}" "${TAG_SHA}" || true
  success "Built and tagged: ${TAG} and ${TAG_SHA}"
done

info "Builds finished for env=${ENV_NAME}"
echo "TIMESTAMP=${TIMESTAMP} GIT_SHA=${GIT_SHA}"
exit 0
