#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
K3S_DIR="$BUNDLE_DIR/artifacts/k3s"

require_linux_amd64() {
  if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "This script must run on Linux AMD64." >&2
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

generate_checksums() {
  (
    cd "$BUNDLE_DIR"
    find artifacts -type f ! -name .gitkeep -print0 \
      | sort -z \
      | xargs -0 --no-run-if-empty sha256sum > checksums.txt
  )
}

require_linux_amd64
require_command curl
require_command find
require_command sha256sum
require_command sort
require_command xargs

mkdir -p "$K3S_DIR"

K3S_VERSION="$(curl -fsSL https://update.k3s.io/v1-release/channels/stable)"
if [[ -z "$K3S_VERSION" || "$K3S_VERSION" != v* ]]; then
  echo "Unable to resolve latest stable K3s version." >&2
  exit 1
fi

BASE_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}"

echo "Downloading K3s ${K3S_VERSION} artifacts..."
curl -fL "$BASE_URL/k3s" -o "$K3S_DIR/k3s"
curl -fL https://get.k3s.io -o "$K3S_DIR/install.sh"
curl -fL "$BASE_URL/k3s-airgap-images-amd64.tar.zst" -o "$K3S_DIR/k3s-airgap-images-amd64.tar.zst"

chmod 0755 "$K3S_DIR/k3s" "$K3S_DIR/install.sh"
chmod 0644 "$K3S_DIR/k3s-airgap-images-amd64.tar.zst"

printf "%s\n" "$K3S_VERSION" > "$K3S_DIR/VERSION"
generate_checksums

echo "Downloaded K3s artifacts to $K3S_DIR"
echo "Updated $BUNDLE_DIR/checksums.txt"
