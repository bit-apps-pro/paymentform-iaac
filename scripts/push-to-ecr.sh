#!/usr/bin/env bash
set -e

# Push images to AWS ECR
# Usage: ./scripts/push-to-ecr.sh --tag <tag> [--region <region>] [--services backend,client]

TAG=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SERVICES_CSV=""

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

function info(){ echo -e "${YELLOW}[INFO]${NC} $1"; }
function success(){ echo -e "${GREEN}[OK]${NC} $1"; }
function error(){ echo -e "${RED}[ERROR]${NC} $1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --services) SERVICES_CSV="$2"; shift 2;;
    -h|--help) cat <<EOF
Push images to ECR.

Usage: $0 --tag <tag> [--region <region>] [--services backend,client]
Example: $0 --tag sandbox-20230101 --region us-east-1 --services backend,client
EOF
      exit 0;;
    *) error "Unknown arg: $1"; exit 1;;
  esac
done

if [ -z "$TAG" ]; then
  error "--tag is required"
  exit 1
fi

command -v aws >/dev/null 2>&1 || { error "aws CLI not found"; exit 1; }
command -v docker >/dev/null 2>&1 || { error "docker not found"; exit 1; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
if [ -z "$ACCOUNT_ID" ]; then
  error "Unable to determine AWS account ID. Ensure aws CLI is configured."; exit 1;
fi

# auth
info "Authenticating to ECR in ${REGION} for account ${ACCOUNT_ID}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com" || { error "ECR login failed"; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_SERVICES=(backend client renderer admin)

IFS=',' read -r -a SERVICES <<< "${SERVICES_CSV:-backend,client,renderer,admin}"

for svc in "${SERVICES[@]}"; do
  LOCAL_TAG="paymentform-${svc}:${TAG}"
  ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/paymentform-${svc}"
  ECR_TAG="${ECR_REPO}:${TAG}"

  info "Re-tagging ${LOCAL_TAG} -> ${ECR_TAG}"
  docker tag "${LOCAL_TAG}" "${ECR_TAG}" || { error "Failed to tag ${LOCAL_TAG} -> ${ECR_TAG}"; exit 1; }

  info "Pushing ${ECR_TAG}"
  docker push "${ECR_TAG}" || { error "Failed to push ${ECR_TAG}"; exit 1; }
  success "Pushed ${ECR_TAG}"
done

info "All requested images pushed to ECR"
exit 0
