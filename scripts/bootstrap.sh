#!/usr/bin/env bash
set -euo pipefail

# Installs the toolchain needed to run the iaac stack:
#
#   tofu, aws, docker, jq, gh, infracost, checkov, trivy
#
# Optional helpers (skipped unless `--with-optional`):
#   wrangler (Cloudflare Workers), cloudflared (CF tunnels), hcloud (Hetzner)
#
# Supports macOS (homebrew) and Linux (Debian/Ubuntu apt + curl install scripts).
# Re-runnable — skips anything already installed.

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; NC="\033[0m"
info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
skip()    { echo -e "${BLUE}[SKIP]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

WITH_OPTIONAL=false
for arg in "$@"; do
  case "${arg}" in
    --with-optional) WITH_OPTIONAL=true ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--with-optional]

Required tools:  tofu, aws, docker, jq, gh, infracost, checkov, trivy
Optional tools:  wrangler, cloudflared, hcloud   (only with --with-optional)
EOF
      exit 0 ;;
    *) error "Unknown arg: ${arg}"; exit 1 ;;
  esac
done

UNAME_S="$(uname -s)"
case "${UNAME_S}" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *) error "Unsupported OS: ${UNAME_S}"; exit 1 ;;
esac

if [[ "${OS}" == "linux" ]]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    error "Only Debian/Ubuntu (apt) is supported on Linux. Install tools manually for other distros."
    exit 1
  fi
  SUDO=""; [[ ${EUID:-$(id -u)} -ne 0 ]] && SUDO="sudo"
fi

if [[ "${OS}" == "mac" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    info "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

# ---------- helpers --------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

brew_install() {
  local pkg="$1"
  if brew list --formula --cask 2>/dev/null | grep -qx "${pkg}"; then
    skip "${pkg} (brew)"
  else
    info "brew install ${pkg}"
    brew install "${pkg}"
  fi
}

apt_install() {
  ${SUDO} apt-get install -y --no-install-recommends "$@"
}

apt_refreshed=false
apt_refresh_once() {
  if ! ${apt_refreshed}; then
    info "apt update"
    ${SUDO} apt-get update -y
    apt_refreshed=true
  fi
}

# ---------- core tools -----------------------------------------------------

install_tofu() {
  if have tofu; then skip "tofu ($(tofu version | head -1))"; return; fi
  info "Installing OpenTofu"
  case "${OS}" in
    mac)   brew_install opentofu ;;
    linux)
      apt_refresh_once
      apt_install ca-certificates curl gnupg
      curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
      chmod +x /tmp/install-opentofu.sh
      ${SUDO} /tmp/install-opentofu.sh --install-method standalone --skip-verify
      rm -f /tmp/install-opentofu.sh
      ;;
  esac
}

install_aws() {
  if have aws; then skip "aws ($(aws --version 2>&1))"; return; fi
  info "Installing AWS CLI"
  case "${OS}" in
    mac)   brew_install awscli ;;
    linux)
      local arch tmp
      arch="$(uname -m)"
      tmp="$(mktemp -d)"
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "${tmp}/awscliv2.zip"
      (cd "${tmp}" && unzip -q awscliv2.zip && ${SUDO} ./aws/install --update)
      rm -rf "${tmp}"
      ;;
  esac
}

install_docker() {
  if have docker; then skip "docker ($(docker --version))"; return; fi
  info "Installing Docker"
  case "${OS}" in
    mac)
      brew_install --cask docker
      info "Open the Docker Desktop app once to finish setup."
      ;;
    linux)
      apt_refresh_once
      apt_install ca-certificates curl gnupg
      ${SUDO} install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg
      local codename
      codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
        | ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null
      ${SUDO} apt-get update -y
      apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ${SUDO} usermod -aG docker "${USER}" || true
      info "Re-login (or run 'newgrp docker') to use docker without sudo."
      ;;
  esac
}

install_jq() {
  if have jq; then skip "jq"; return; fi
  case "${OS}" in
    mac)   brew_install jq ;;
    linux) apt_refresh_once; apt_install jq ;;
  esac
}

install_gh() {
  if have gh; then skip "gh ($(gh --version | head -1))"; return; fi
  info "Installing GitHub CLI"
  case "${OS}" in
    mac)   brew_install gh ;;
    linux)
      apt_refresh_once
      apt_install ca-certificates curl gnupg
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | ${SUDO} dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      ${SUDO} chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | ${SUDO} tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      ${SUDO} apt-get update -y
      apt_install gh
      ;;
  esac
}

install_infracost() {
  if have infracost; then skip "infracost ($(infracost --version))"; return; fi
  info "Installing Infracost"
  case "${OS}" in
    mac)   brew_install infracost ;;
    linux) curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | ${SUDO} sh ;;
  esac
}

install_checkov() {
  if have checkov; then skip "checkov ($(checkov --version))"; return; fi
  info "Installing Checkov"
  if have pipx; then
    pipx install checkov
  elif have pip3; then
    pip3 install --user checkov
  elif have pip; then
    pip install --user checkov
  else
    case "${OS}" in
      mac)   brew_install pipx; pipx install checkov ;;
      linux) apt_refresh_once; apt_install python3-pip pipx; pipx ensurepath; pipx install checkov ;;
    esac
  fi
}

install_trivy() {
  if have trivy; then skip "trivy ($(trivy --version | head -1))"; return; fi
  info "Installing Trivy"
  case "${OS}" in
    mac)   brew_install trivy ;;
    linux)
      apt_refresh_once
      apt_install wget gnupg lsb-release
      wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
        | ${SUDO} gpg --dearmor -o /usr/share/keyrings/trivy.gpg
      echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
        | ${SUDO} tee /etc/apt/sources.list.d/trivy.list >/dev/null
      ${SUDO} apt-get update -y
      apt_install trivy
      ;;
  esac
}

# ---------- optional helpers ----------------------------------------------

install_wrangler() {
  if have wrangler; then skip "wrangler"; return; fi
  info "Installing wrangler (Cloudflare Workers CLI)"
  if ! have npm; then
    case "${OS}" in
      mac)   brew_install node ;;
      linux) apt_refresh_once; apt_install nodejs npm ;;
    esac
  fi
  ${SUDO:-} npm install -g wrangler
}

install_cloudflared() {
  if have cloudflared; then skip "cloudflared"; return; fi
  info "Installing cloudflared"
  case "${OS}" in
    mac)   brew_install cloudflared ;;
    linux)
      apt_refresh_once
      curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | ${SUDO} tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -sc) main" \
        | ${SUDO} tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
      ${SUDO} apt-get update -y
      apt_install cloudflared
      ;;
  esac
}

install_hcloud() {
  if have hcloud; then skip "hcloud"; return; fi
  info "Installing Hetzner Cloud CLI"
  case "${OS}" in
    mac)   brew_install hcloud ;;
    linux)
      local arch tag tmp
      arch="$(uname -m)"; [[ "${arch}" == "x86_64" ]] && arch="amd64"; [[ "${arch}" == "aarch64" ]] && arch="arm64"
      tag="$(curl -fsSL https://api.github.com/repos/hetznercloud/cli/releases/latest | grep -oE '"tag_name":\s*"[^"]+"' | cut -d\" -f4)"
      tmp="$(mktemp -d)"
      curl -fsSL "https://github.com/hetznercloud/cli/releases/download/${tag}/hcloud-linux-${arch}.tar.gz" \
        -o "${tmp}/hcloud.tar.gz"
      tar -xzf "${tmp}/hcloud.tar.gz" -C "${tmp}"
      ${SUDO} install -m 0755 "${tmp}/hcloud" /usr/local/bin/hcloud
      rm -rf "${tmp}"
      ;;
  esac
}

# ---------- run ------------------------------------------------------------

info "Detected OS: ${OS}"
info "Installing core tools..."
install_tofu
install_aws
install_docker
install_jq
install_gh
install_infracost
install_checkov
install_trivy

if ${WITH_OPTIONAL}; then
  info "Installing optional tools..."
  install_wrangler
  install_cloudflared
  install_hcloud
else
  info "Skipping optional tools (wrangler, cloudflared, hcloud). Re-run with --with-optional to install."
fi

success "Bootstrap finished."
echo
echo "Next steps:"
echo "  - Configure AWS:        aws configure"
echo "  - Login to GHCR:        echo \$GHCR_TOKEN | docker login ghcr.io -u <user> --password-stdin"
echo "  - Infracost API key:    infracost auth login"
echo "  - GitHub CLI auth:      gh auth login"
echo "  - Init terraform:       make init"
