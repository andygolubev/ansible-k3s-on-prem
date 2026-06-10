#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

required_files=(
  "artifacts/k3s/k3s"
  "artifacts/k3s/install.sh"
  "artifacts/k3s/k3s-airgap-images-amd64.tar.zst"
  "checksums.txt"
)

missing=0
for file in "${required_files[@]}"; do
  if [[ ! -f "$BUNDLE_DIR/$file" ]]; then
    echo "Missing required file: $file" >&2
    missing=1
  fi
done

if ! find "$BUNDLE_DIR/artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps" -maxdepth 1 -type f -name '*.deb' | grep -q .; then
  echo "Missing required Ansible .deb packages." >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

if [[ ! -s "$BUNDLE_DIR/checksums.txt" ]]; then
  echo "checksums.txt is empty. Run the download scripts first." >&2
  exit 1
fi

(
  cd "$BUNDLE_DIR"
  sha256sum --check checksums.txt
)

if [[ ! -x "$BUNDLE_DIR/artifacts/k3s/k3s" ]]; then
  echo "K3s binary is not executable." >&2
  exit 1
fi

if [[ ! -x "$BUNDLE_DIR/artifacts/k3s/install.sh" ]]; then
  echo "K3s install script is not executable." >&2
  exit 1
fi

echo "Offline bundle artifacts verified."
