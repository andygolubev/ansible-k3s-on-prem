#!/usr/bin/env bash
# Downloads operator CLI tools for offline target installation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
TOOLS_DIR="$PAYLOAD_DIR/tools"
BIN_DIR="$PAYLOAD_DIR/bin"

K9S_VERSION="${K9S_VERSION:-v0.32.7}"
K9S_ARCHIVE_URL="${K9S_ARCHIVE_URL:-https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz}"

usage() {
  cat <<'USAGE'
Usage: download-operator-tools.sh [--k9s-version VERSION]

Downloads operator tools for offline installation.

Environment:
  K9S_VERSION       k9s release tag (default: v0.32.7)
  K9S_ARCHIVE_URL   full k9s Linux AMD64 archive URL override
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --k9s-version)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --k9s-version" >&2
        exit 1
      fi
      K9S_VERSION="$2"
      K9S_ARCHIVE_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command curl
require_command sha256sum
require_command tar

mkdir -p "$TOOLS_DIR/k9s" "$BIN_DIR"

archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT

echo "Downloading k9s ${K9S_VERSION}..."
curl -fL "$K9S_ARCHIVE_URL" -o "$archive"
tar -xzf "$archive" -C "$TOOLS_DIR/k9s" k9s
chmod 0755 "$TOOLS_DIR/k9s/k9s"
cp "$TOOLS_DIR/k9s/k9s" "$BIN_DIR/k9s"
chmod 0755 "$BIN_DIR/k9s"
echo "$K9S_VERSION" > "$TOOLS_DIR/k9s/VERSION"

generate_checksums

echo "Downloaded k9s ${K9S_VERSION} to $TOOLS_DIR/k9s"
echo "Updated $PAYLOAD_DIR/checksums.txt"
