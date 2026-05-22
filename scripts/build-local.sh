#!/usr/bin/env bash
set -euo pipefail

# Universal local builder. Builds the full base + app chain so nothing has to
# be pulled from GHCR.
#
# Backend has two variants selected via VARIANT (env) or as the third arg:
#   - nginx       (default) — php-fpm + nginx, libsql NTS
#   - frankenphp             — single binary, libsql ZTS, custom xcaddy build
#
# Chain (nginx variant):
#   1. libsql-base    backend/.docker/nginx/Dockerfile.libsql-base          (NTS)
#   2. backend-base   backend/.docker/nginx/Dockerfile.backend-base         (uses libsql-base)
#   3. backend        backend/.docker/Dockerfile                            (uses backend-base)
#
# Chain (frankenphp variant):
#   1. libsql-base    backend/.docker/frankenphp/Dockerfile.libsql-base     (ZTS)
#   2. frankenphp     backend/.docker/frankenphp/Dockerfile.frankenphp-base (xcaddy build)
#   3. backend-base   backend/.docker/frankenphp/Dockerfile.backend-base    (uses libsql-base + frankenphp)
#   4. backend        backend/.docker/Dockerfile                            (uses backend-base)
#
# Shared chain:
#   - renderer-base   renderer/.docker/Dockerfile.base
#   - renderer        renderer/.docker/Dockerfile (uses renderer-base)
#   - client          client/.docker/Dockerfile
#   - admin           admin/.docker/Dockerfile
#
# Local tag names mirror the GHCR refs the parent Dockerfile defaults to so
# child stages resolve to the locally-built image with no FROM rewrites:
#   ghcr.io/bit-apps-pro/paymentform-libsql-{nts,zts}:local
#   ghcr.io/bit-apps-pro/paymentform-frankenphp:local
#   ghcr.io/bit-apps-pro/paymentform-base-image-{nginx,frankenphp}:local
#   ghcr.io/bit-apps-pro/paymentform-renderer-base:latest
#
# Each also gets `paymentform-<name>:<env>-<timestamp>` and `:<env>-<git-sha>`.

ENV_NAME="${1:-}"
TARGET="${2:-all}"
# VARIANT resolution order:
#   1. VARIANT env var (CI / scripted)
#   2. third positional arg
#   3. interactive prompt when stdin is a TTY
#   4. fall back to nginx
VARIANT_ARG="${VARIANT:-${3:-}}"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; NC="\033[0m"
info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
note()    { echo -e "${BLUE}[NOTE]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $0 <env> [target] [variant]
  env:     dev | sandbox | prod
  target:  all                 (default — bases + apps)
           bases               libsql-base + backend-base + renderer-base [+ frankenphp]
           apps                backend + client + renderer + admin
           libsql-base | frankenphp-base | backend-base | renderer-base
           backend | client | renderer | admin
  variant: nginx (default) | frankenphp     (also via VARIANT=… env)

Env vars:
  VARIANT        backend variant: nginx | frankenphp
  PLATFORM       buildx --platform (e.g. linux/amd64)

Examples:
  $0 prod                                 # all bases + apps, nginx backend
  $0 prod backend frankenphp              # only backend, frankenphp chain
  VARIANT=frankenphp $0 prod              # everything on frankenphp chain

Tags emitted:
  <local-ghcr-ref>:local                     (so child FROMs resolve)
  paymentform-<svc>:<env>-<timestamp>
  paymentform-<svc>:<env>-<git-sha>
EOF
}

if [[ "${ENV_NAME}" == "--help" || "${ENV_NAME}" == "-h" || -z "${ENV_NAME}" ]]; then
  usage; exit 0
fi

command -v docker >/dev/null 2>&1 || { error "docker not found"; exit 1; }

# Resolve backend variant — prompt only if backend chain is actually being built
# and nothing was provided explicitly.
prompt_variant() {
  if [[ ! -t 0 ]]; then
    info "No TTY; defaulting VARIANT=nginx (override via VARIANT=… or third arg)"
    echo nginx
    return
  fi
  local choice
  echo "Backend variant?" >&2
  PS3="Select [1-2]: "
  select choice in nginx frankenphp; do
    case "${choice}" in
      nginx|frankenphp) echo "${choice}"; return ;;
      *) echo "Invalid selection. Pick 1 or 2." >&2 ;;
    esac
  done < /dev/tty
}

backend_touched() {
  case "${TARGET}" in
    all|bases|apps|backend|backend-base|libsql-base|frankenphp-base) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ -z "${VARIANT_ARG}" ]] && backend_touched; then
  VARIANT="$(prompt_variant)"
elif [[ -z "${VARIANT_ARG}" ]]; then
  VARIANT="nginx"
else
  VARIANT="${VARIANT_ARG}"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
GIT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo local)"
PLATFORM_ARGS=()
[[ -n "${PLATFORM:-}" ]] && PLATFORM_ARGS=(--platform "${PLATFORM}")

# Local image refs that match the Dockerfile defaults so FROMs auto-resolve.
# Variant-specific refs picked below.
case "${VARIANT}" in
  nginx)
    LIBSQL_LOCAL_REF="ghcr.io/bit-apps-pro/paymentform-libsql-nts:local"
    BACKEND_BASE_LOCAL_REF="ghcr.io/bit-apps-pro/paymentform-base-image-nginx:local"
    FRANKENPHP_LOCAL_REF=""  # not used in nginx chain
    BACKEND_LIBSQL_DOCKERFILE="backend/.docker/nginx/Dockerfile.libsql-base"
    BACKEND_BASE_DOCKERFILE="backend/.docker/nginx/Dockerfile.backend-base"
    ;;
  frankenphp)
    LIBSQL_LOCAL_REF="ghcr.io/bit-apps-pro/paymentform-libsql-zts:local"
    FRANKENPHP_LOCAL_REF="ghcr.io/bit-apps-pro/paymentform-frankenphp:local"
    BACKEND_BASE_LOCAL_REF="ghcr.io/bit-apps-pro/paymentform-base-image-frankenphp:local"
    BACKEND_LIBSQL_DOCKERFILE="backend/.docker/frankenphp/Dockerfile.libsql-base"
    BACKEND_BASE_DOCKERFILE="backend/.docker/frankenphp/Dockerfile.backend-base"
    FRANKENPHP_DOCKERFILE="backend/.docker/frankenphp/Dockerfile.frankenphp-base"
    ;;
  *)
    error "Unknown VARIANT: ${VARIANT}. Pick nginx or frankenphp."
    exit 1
    ;;
esac
RENDERER_BASE_LOCAL_REF="ghcr.io/bit-apps-pro/paymentform-renderer-base:latest"
info "Backend variant: ${VARIANT}"

# ---------- build helpers --------------------------------------------------

# Build with multiple tags. Args: <context> <dockerfile> <target_or_empty> <primary-tag> [extra-tag ...]
build_image() {
  local ctx="$1" df="$2" target="$3" primary="$4"
  shift 4
  local -a tags=(-t "${primary}")
  for t in "$@"; do tags+=(-t "${t}"); done

  local -a target_args=()
  [[ -n "${target}" ]] && target_args=(--target "${target}")

  info "Build → ${primary}"
  info "  context:    ${ctx}"
  info "  dockerfile: ${df}"
  [[ -n "${target}" ]] && info "  target:     ${target}"

  docker build \
    --progress=plain \
    "${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"}" \
    -f "${df}" \
    "${target_args[@]+"${target_args[@]}"}" \
    "${tags[@]}" \
    "${ctx}"
  success "${primary}"
}

versioned_tags() {
  local svc="$1"
  echo "paymentform-${svc}:${ENV_NAME}-${TIMESTAMP} paymentform-${svc}:${ENV_NAME}-${GIT_SHA}"
}

# ---------- per-image build functions -------------------------------------

build_libsql_base() {
  local ctx="${REPO_ROOT}/backend"
  local df="${REPO_ROOT}/${BACKEND_LIBSQL_DOCKERFILE}"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  # The libsql Dockerfile has a multi-stage build; the published image is the
  # `libsql-base` stage (FROM scratch). Lock to that target.
  # shellcheck disable=SC2046
  build_image "${ctx}" "${df}" "libsql-base" "${LIBSQL_LOCAL_REF}" $(versioned_tags libsql-base-${VARIANT})
}

build_frankenphp_base() {
  [[ "${VARIANT}" != "frankenphp" ]] && { error "frankenphp-base only valid with VARIANT=frankenphp"; return 1; }
  local ctx="${REPO_ROOT}/backend"
  local df="${REPO_ROOT}/${FRANKENPHP_DOCKERFILE}"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  # shellcheck disable=SC2046
  build_image "${ctx}" "${df}" "" "${FRANKENPHP_LOCAL_REF}" $(versioned_tags frankenphp-base)
}

build_backend_base() {
  # ctx is .docker/ (not backend/) to match CI in build-base-image-{nginx,frankenphp}.yml.
  # Dockerfile.backend-base does `COPY nginx/<f>` or `COPY frankenphp/<f>` — both
  # resolve only when the build context is .docker/.
  local ctx="${REPO_ROOT}/backend/.docker"
  local df="${REPO_ROOT}/${BACKEND_BASE_DOCKERFILE}"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  ensure_image "${LIBSQL_LOCAL_REF}" build_libsql_base

  declare -a build_args=(--build-arg "LIBSQL_BASE_IMAGE=${LIBSQL_LOCAL_REF}")
  if [[ "${VARIANT}" == "frankenphp" ]]; then
    ensure_image "${FRANKENPHP_LOCAL_REF}" build_frankenphp_base
    build_args+=(--build-arg "FRANKENPHP_BASE_IMAGE=${FRANKENPHP_LOCAL_REF}")
    info "  build-arg FRANKENPHP_BASE_IMAGE=${FRANKENPHP_LOCAL_REF}"
  fi
  info "  build-arg LIBSQL_BASE_IMAGE=${LIBSQL_LOCAL_REF}"
  # shellcheck disable=SC2046
  docker build \
    --progress=plain \
    "${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"}" \
    -f "${df}" \
    "${build_args[@]}" \
    -t "${BACKEND_BASE_LOCAL_REF}" \
    $(printf -- '-t %s ' $(versioned_tags backend-base-${VARIANT})) \
    "${ctx}"
  success "${BACKEND_BASE_LOCAL_REF}"
}

build_backend() {
  local ctx="${REPO_ROOT}/backend"
  local df="${ctx}/.docker/Dockerfile"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  ensure_image "${BACKEND_BASE_LOCAL_REF}" build_backend_base
  info "  build-arg BASE_IMAGE=${BACKEND_BASE_LOCAL_REF}"
  # shellcheck disable=SC2046
  docker build \
    --progress=plain \
    "${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"}" \
    -f "${df}" \
    --build-arg "BASE_IMAGE=${BACKEND_BASE_LOCAL_REF}" \
    $(printf -- '-t %s ' $(versioned_tags backend-${VARIANT})) \
    "${ctx}"
  success "paymentform-backend-${VARIANT} tagged"
}

build_renderer_base() {
  local ctx="${REPO_ROOT}/renderer"
  local df="${ctx}/.docker/Dockerfile.base"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  # shellcheck disable=SC2046
  build_image "${ctx}" "${df}" "" "${RENDERER_BASE_LOCAL_REF}" $(versioned_tags renderer-base)
}

build_renderer() {
  local ctx="${REPO_ROOT}/renderer"
  local df="${ctx}/.docker/Dockerfile"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  ensure_image "${RENDERER_BASE_LOCAL_REF}" build_renderer_base
  # shellcheck disable=SC2046
  build_image "${ctx}" "${df}" "" "paymentform-renderer:${ENV_NAME}-${TIMESTAMP}" \
    "paymentform-renderer:${ENV_NAME}-${GIT_SHA}"
}

build_client() {
  local ctx="${REPO_ROOT}/client"
  local df="${ctx}/.docker/Dockerfile"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  build_image "${ctx}" "${df}" "" "paymentform-client:${ENV_NAME}-${TIMESTAMP}" \
    "paymentform-client:${ENV_NAME}-${GIT_SHA}"
}

build_admin() {
  local ctx="${REPO_ROOT}/admin"
  local df="${ctx}/.docker/Dockerfile"
  [[ -f "${df}" ]] || { error "missing ${df}"; return 1; }
  build_image "${ctx}" "${df}" "" "paymentform-admin:${ENV_NAME}-${TIMESTAMP}" \
    "paymentform-admin:${ENV_NAME}-${GIT_SHA}"
}

# Build dependency only when the image isn't already in the local daemon.
ensure_image() {
  local ref="$1" builder="$2"
  if docker image inspect "${ref}" >/dev/null 2>&1; then
    note "Reusing local ${ref}"
  else
    info "Missing ${ref} — building dependency"
    "${builder}"
  fi
}

# ---------- dispatch -------------------------------------------------------

case "${TARGET}" in
  all)
    build_libsql_base
    [[ "${VARIANT}" == "frankenphp" ]] && build_frankenphp_base
    build_backend_base
    build_backend
    build_renderer_base
    build_renderer
    build_client
    build_admin
    ;;
  bases)
    build_libsql_base
    [[ "${VARIANT}" == "frankenphp" ]] && build_frankenphp_base
    build_backend_base
    build_renderer_base
    ;;
  apps)
    build_backend
    build_renderer
    build_client
    build_admin
    ;;
  libsql-base)    build_libsql_base ;;
  frankenphp-base) build_frankenphp_base ;;
  backend-base)   build_backend_base ;;
  renderer-base)  build_renderer_base ;;
  backend)        build_backend ;;
  renderer)       build_renderer ;;
  client)         build_client ;;
  admin)          build_admin ;;
  *) error "Unknown target: ${TARGET}"; usage; exit 1 ;;
esac

success "Builds finished. env=${ENV_NAME} timestamp=${TIMESTAMP} git_sha=${GIT_SHA}"
