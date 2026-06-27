#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_TIME="${SECONDS}"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  GREEN=$'\033[32m'
  BLUE=$'\033[34m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  BOLD="" GREEN="" BLUE="" RED="" RESET=""
fi

log() {
  printf '%s[%(%Y-%m-%d %H:%M:%S)T]%s %s\n' "${BLUE}" -1 "${RESET}" "$*"
}

stage() {
  printf '\n%s%s==> %s%s\n' "${BOLD}" "${GREEN}" "$*" "${RESET}"
}

die() {
  printf '\n%sERROR:%s %s\n' "${RED}" "${RESET}" "$*" >&2
  exit 1
}

on_error() {
  local rc=$?
  printf '\n%sInstallation failed%s at line %s (exit code %s).\n' \
    "${RED}" "${RESET}" "${BASH_LINENO[0]}" "${rc}" >&2
  printf 'Correct the error and rerun %s; the installer and Ansible playbook are idempotent.\n' "$0" >&2
  exit "${rc}"
}
trap on_error ERR

if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null || die "Run this installer as root (sudo is not installed)."
  log "Elevating with sudo..."
  exec sudo --preserve-env=TERM "${BASH_SOURCE[0]}" "$@"
fi

stage "Offline K3s installation"
log "Bundle directory: ${BUNDLE_ROOT}"
log "This installer uses local payload files only; it does not provision infrastructure."

stage "1/5 Preflight checks"
[[ "$(uname -m)" == "x86_64" ]] || die "Unsupported architecture: $(uname -m); expected x86_64."
[[ -r /etc/os-release ]] || die "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Unsupported OS: ${ID:-unknown}; expected Ubuntu."
[[ "${VERSION_ID:-}" == "26.04" ]] || die "Unsupported Ubuntu version: ${VERSION_ID:-unknown}; expected 26.04."
[[ -x "${BUNDLE_ROOT}/scripts/verify-artifacts.sh" ]] || die "Offline bundle not found beside install.sh."
[[ -f "${BUNDLE_ROOT}/payload/tools/k9s/k9s" ]] || die "k9s payload is missing."
[[ -f "${BUNDLE_ROOT}/payload/observability/images/images.tsv" ]] || die "Observability payload is missing."
available_kib="$(df -Pk "${BUNDLE_ROOT}" | awk 'NR == 2 {print $4}')"
log "Host: $(hostname)"
log "OS: ${PRETTY_NAME}"
log "Architecture: $(uname -m)"
log "Free space on target filesystem: $((available_kib / 1024 / 1024)) GiB"
((available_kib >= 80 * 1024 * 1024)) || die "At least 80 GiB of free disk space is required."

stage "2/5 Verify offline payload checksums"
log "Checking every bundled package, image, model file, and manifest. This can take several minutes."
"${BUNDLE_ROOT}/scripts/verify-artifacts.sh"

stage "3/5 Bootstrap Ansible from local packages"
log "Installing Ansible without contacting package repositories."
"${BUNDLE_ROOT}/scripts/install-ansible-offline.sh"
ansible-playbook --version | sed -n '1,2p'

stage "4/5 Install the complete stack"
log "Running K3s, GPU, Argo CD, k9s, observability, and vLLM roles."
log "Ansible verbose output is enabled; task names show current progress."
cd "${BUNDLE_ROOT}/ansible"
ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-1}" \
  ansible-playbook -v -i inventory.ini playbooks/site.yml

stage "5/5 Final status"
/usr/local/bin/k3s kubectl get nodes -o wide
/usr/local/bin/k3s kubectl get pods -A
elapsed=$((SECONDS - START_TIME))
printf '\n%sInstallation completed successfully%s in %dm %02ds.\n' \
  "${GREEN}" "${RESET}" "$((elapsed / 60))" "$((elapsed % 60))"
printf 'Validate the deployment with: %s\n' "${BUNDLE_ROOT}/VALIDATION.md"
