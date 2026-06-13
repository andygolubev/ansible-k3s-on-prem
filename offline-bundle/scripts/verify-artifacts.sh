#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"

required_files=(
  "payload/k3s/k3s"
  "payload/k3s/install.sh"
  "payload/k3s/k3s-airgap-images-amd64.tar.zst"
  "payload/checksums.txt"
)

missing=0
for file in "${required_files[@]}"; do
  if [[ ! -f "$BUNDLE_DIR/$file" ]]; then
    echo "Missing required file: $file" >&2
    missing=1
  fi
done

if [[ -z "$(find "$BUNDLE_DIR/payload/debs/ubuntu-26.04-amd64/ansible-and-deps" -maxdepth 1 -type f -name '*.deb' -print -quit)" ]]; then
  echo "Missing required Ansible .deb packages." >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

if [[ ! -s "$PAYLOAD_DIR/checksums.txt" ]]; then
  echo "payload/checksums.txt is empty. Run the download scripts first." >&2
  exit 1
fi

(
  cd "$PAYLOAD_DIR"
  sha256sum --check checksums.txt
)

if [[ ! -x "$BUNDLE_DIR/payload/k3s/k3s" ]]; then
  echo "K3s binary is not executable." >&2
  exit 1
fi

if [[ ! -x "$BUNDLE_DIR/payload/k3s/install.sh" ]]; then
  echo "K3s install script is not executable." >&2
  exit 1
fi

echo "Offline bundle artifacts verified."
