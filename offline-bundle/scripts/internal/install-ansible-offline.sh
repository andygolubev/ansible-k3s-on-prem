#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEB_DIR="$BUNDLE_DIR/payload/debs/ubuntu-26.04-amd64/ansible-and-deps"
HOST_TOOL_MANIFEST="$BUNDLE_DIR/payload/debs/ubuntu-26.04-amd64/HOST_TOOL_PACKAGES"

if [[ ! -d "$DEB_DIR" ]]; then
  echo "Missing package directory: $DEB_DIR" >&2
  exit 1
fi

shopt -s nullglob
DEBS=("$DEB_DIR"/*.deb)
shopt -u nullglob

if [[ "${#DEBS[@]}" -eq 0 ]]; then
  echo "No .deb packages found in $DEB_DIR" >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo ./scripts/internal/install-ansible-offline.sh" >&2
  exit 1
fi

dpkg -i "${DEBS[@]}" || apt-get install -f -y --no-download

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook is still unavailable after local package installation." >&2
  exit 1
fi

if [[ -s "$HOST_TOOL_MANIFEST" ]]; then
  missing_tools=()
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii' \
      || missing_tools+=("$package")
  done < "$HOST_TOOL_MANIFEST"
  if [[ "${#missing_tools[@]}" -ne 0 ]]; then
    echo "Offline host tools failed to install: ${missing_tools[*]}" >&2
    exit 1
  fi
else
  echo "Host-tool manifest is absent; installing legacy Ansible payload only." >&2
fi

echo "Ansible and offline host tools installed from local packages."
