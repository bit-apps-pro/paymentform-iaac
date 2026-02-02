#!/usr/bin/env bash
set -e

# Build local Docker images for development (no registry)
# Usage: ./scripts/build-local-dev.sh [service]

SERVICE_FILTER="$1"

# colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

function info(){ echo -e "${YELLOW}[INFO]${NC} $1"; }
function success(){ echo -e "${GREEN}[OK]${NC} $1"; }
function error(){ echo -e "${RED}[ERROR]${NC} $1"; }

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  cat <<EOF
Build local dev images for all services or a single service.

Usage: $0 [service]
service: backend | client | renderer | admin (optional)
EOF
  exit 0
fi

# prerequisites
command -v docker >/dev/null 2>&1 || { error "docker not found in PATH"; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=(backend client renderer admin)

if [ -n "${SERVICE_FILTER}" ]; then
  SERVICES=("${SERVICE_FILTER}")
fi

for svc in "${SERVICES[@]}"; do
  BUILD_CTX="${ROOT_DIR}/../${svc}"
  TAG="paymentform-${svc}:dev-local"

  info "Building ${svc} from ${BUILD_CTX} -> ${TAG}"
  if [ ! -d "${BUILD_CTX}" ]; then
    error "Context directory not found: ${BUILD_CTX}, skipping ${svc}"
    continue
  fi

  docker build --progress=plain -t "${TAG}" "${BUILD_CTX}" || { error "Failed to build ${svc}"; exit 1; }
  success "Built ${TAG}"
done

info "All requested builds complete"
exit 0
