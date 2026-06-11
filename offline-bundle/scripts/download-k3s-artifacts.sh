#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
K3S_DIR="$PAYLOAD_DIR/k3s"
K3S_LATEST_URL="${K3S_LATEST_URL:-https://github.com/k3s-io/k3s/releases/latest}"
VERBOSE="${VERBOSE:-0}"
K3S_VERSION_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: download-k3s-artifacts.sh [--k3s-version VERSION] [--verbose]

Downloads K3s artifacts for Linux AMD64.

Options:
  --k3s-version VERSION  Download a specific K3s version, for example v1.33.1+k3s1.
  --verbose              Print troubleshooting details.

Environment:
  VERBOSE=1              Same as --verbose.
  K3S_LATEST_URL=URL     Override the GitHub latest-release endpoint.
USAGE
}

log_verbose() {
  if [[ "$VERBOSE" == "1" || "$VERBOSE" == "true" ]]; then
    echo "DEBUG: $*" >&2
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --k3s-version)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        echo "Missing value for --k3s-version" >&2
        exit 1
      fi
      K3S_VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=1
      shift
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

urlencode_k3s_version() {
  printf "%s" "$1" | sed 's/+/%2B/g'
}

resolve_k3s_version() {
  if [[ -n "$K3S_VERSION_OVERRIDE" ]]; then
    printf "%s\n" "$K3S_VERSION_OVERRIDE"
    return 0
  fi

  local effective_url
  local curl_status

  set +e
  effective_url="$(
    curl -fsSIL -o /dev/null -w '%{url_effective}' "$K3S_LATEST_URL" 2>&1
  )"
  curl_status="$?"
  set -e

  log_verbose "uname -s: $(uname -s)"
  log_verbose "uname -m: $(uname -m)"
  log_verbose "latest URL: $K3S_LATEST_URL"
  log_verbose "curl status: $curl_status"
  log_verbose "effective release URL: $effective_url"

  if [[ "$curl_status" -ne 0 ]]; then
    echo "Unable to query K3s latest release endpoint: $K3S_LATEST_URL" >&2
    echo "curl exit status: $curl_status" >&2
    echo "curl output: $effective_url" >&2
    return 1
  fi

  local version
  version="${effective_url##*/}"
  version="$(printf "%s" "$version" | sed 's/%2B/+/g; s/%2b/+/g' | tr -d '[:space:]')"

  if [[ -z "$version" || "$version" != v* || "$version" == *"/"* ]]; then
    echo "Unable to resolve latest stable K3s version." >&2
    echo "Expected GitHub to redirect to a release URL ending in vX.Y.Z+k3sN." >&2
    echo "Effective URL: $effective_url" >&2
    echo "Retry with --verbose, or pass --k3s-version vX.Y.Z+k3sN." >&2
    return 1
  fi

  printf "%s\n" "$version"
}

generate_checksums() {
  (
    cd "$PAYLOAD_DIR"
    find . -type f ! -name checksums.txt -print0 \
      | sort -z \
      | xargs -0 --no-run-if-empty sha256sum > checksums.txt
  )
}

require_linux_amd64
require_command curl
require_command find
require_command sed
require_command sha256sum
require_command sort
require_command xargs

mkdir -p "$K3S_DIR"

K3S_VERSION="$(resolve_k3s_version)"
K3S_VERSION_URL="$(urlencode_k3s_version "$K3S_VERSION")"

BASE_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION_URL}"
log_verbose "release base URL: $BASE_URL"

echo "Downloading K3s ${K3S_VERSION} artifacts..."
curl -fL "$BASE_URL/k3s" -o "$K3S_DIR/k3s"
curl -fL https://get.k3s.io -o "$K3S_DIR/install.sh"
curl -fL "$BASE_URL/k3s-airgap-images-amd64.tar.zst" -o "$K3S_DIR/k3s-airgap-images-amd64.tar.zst"

chmod 0755 "$K3S_DIR/k3s" "$K3S_DIR/install.sh"
chmod 0644 "$K3S_DIR/k3s-airgap-images-amd64.tar.zst"

printf "%s\n" "$K3S_VERSION" > "$K3S_DIR/VERSION"
generate_checksums

echo "Downloaded K3s artifacts to $K3S_DIR"
echo "Updated $PAYLOAD_DIR/checksums.txt"
