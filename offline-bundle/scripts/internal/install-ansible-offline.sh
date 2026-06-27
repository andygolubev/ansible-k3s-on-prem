#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEB_DIR="$BUNDLE_DIR/payload/debs/ubuntu-26.04-amd64/ansible-and-deps"

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

echo "Ansible installed from local packages."
