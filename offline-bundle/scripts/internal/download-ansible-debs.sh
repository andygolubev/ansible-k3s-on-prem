#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
DEB_DIR="$PAYLOAD_DIR/debs/ubuntu-26.04-amd64/ansible-and-deps"

PACKAGES=(
  ansible
  ansible-core
  git
  python3
  sudo
)

require_linux_amd64() {
  if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "This script must run on Linux AMD64." >&2
    exit 1
  fi
}

require_ubuntu_2604() {
  if [[ ! -r /etc/os-release ]]; then
    echo "Cannot verify OS: /etc/os-release is missing." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" ]]; then
    echo "This script must run on Ubuntu 26.04 AMD64 or a compatible clean environment." >&2
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    require_command sudo
    sudo "$@"
  fi
}

generate_checksums() {
  [[ "${DEFER_CHECKSUMS:-0}" == "1" ]] && return
  (
    cd "$PAYLOAD_DIR"
    find . -type f ! -name checksums.txt -print0 \
      | sort -z \
      | xargs -0 --no-run-if-empty sha256sum > checksums.txt
  )
}

require_linux_amd64
require_ubuntu_2604
require_command apt-cache
require_command apt-get
require_command awk
require_command find
require_command grep
require_command sha256sum
require_command sort
require_command sed
require_command xargs

mkdir -p "$DEB_DIR"

echo "Updating apt metadata..."
as_root apt-get update

echo "Resolving Ansible packages and dependencies..."
mapfile -t RESOLVED_PACKAGES < <(
  apt-cache depends --recurse \
    --no-recommends \
    --no-suggests \
    --no-conflicts \
    --no-breaks \
    --no-replaces \
    --no-enhances \
    "${PACKAGES[@]}" \
    | awk '
        /^[[:alnum:]][[:alnum:].+:-]*$/ { print $1; next }
        /^[[:space:]]*(PreDepends|Depends):/ { print $2 }
      ' \
    | sed 's/:any$//' \
    | grep -E '^[[:alnum:]][[:alnum:].+-]+$' \
    | sort -u
)

if [[ "${#RESOLVED_PACKAGES[@]}" -eq 0 ]]; then
  echo "No packages were resolved." >&2
  exit 1
fi

echo "Downloading ${#RESOLVED_PACKAGES[@]} packages..."
(
  cd "$DEB_DIR"
  apt-get download "${RESOLVED_PACKAGES[@]}"
)

if [[ -z "$(find "$DEB_DIR" -maxdepth 1 -type f -name '*.deb' -print -quit)" ]]; then
  echo "No .deb packages were downloaded to $DEB_DIR" >&2
  exit 1
fi

generate_checksums

echo "Downloaded Ansible .deb packages to $DEB_DIR"
echo "Updated $PAYLOAD_DIR/checksums.txt"
