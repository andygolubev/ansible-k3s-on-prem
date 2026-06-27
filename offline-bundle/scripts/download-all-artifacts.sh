#!/usr/bin/env bash
# Build the complete generated payload for a fully isolated installation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERNAL_DIR="$SCRIPT_DIR/internal"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
STATE_DIR="$PAYLOAD_DIR/.download-state"
CLEAN=0
ASSUME_YES=0

usage() {
  cat <<'USAGE'
Usage: download-all-artifacts.sh [--clean] [--yes]

Downloads/builds every generated artifact required by install.sh, writes one
final checksum manifest, and verifies the completed payload.

On other operating systems, the script automatically runs itself in an
Ubuntu 26.04 AMD64 Docker container. Docker must be running and at least 50 GB
of free disk space must be available.

Options:
  --clean  Delete the existing gitignored payload before downloading.
  --yes    Do not prompt for confirmation with --clean.

Individual version overrides remain available as environment variables, such
as K9S_VERSION, VLLM_IMAGE, MODEL_ID, MODEL_REVISION, NVIDIA_DRIVER_BRANCH,
DEVICE_PLUGIN_VERSION, and AGENT_IMAGE.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

run_in_docker() {
  command -v docker >/dev/null 2>&1 || {
    echo "Docker is required to start the Ubuntu 26.04 AMD64 downloader." >&2
    exit 1
  }
  docker info >/dev/null 2>&1 || {
    echo "Docker is installed but its daemon is not available." >&2
    exit 1
  }

  local docker_host socket_path
  docker_host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  socket_path="${docker_host#unix://}"
  if [[ "$docker_host" != unix://* || ! -S "$socket_path" ]]; then
    echo "The active Docker context does not expose a Unix socket." >&2
    echo "A Docker socket is required because the downloader pulls and saves images." >&2
    exit 1
  fi

  local -a docker_args=(
    run --rm --platform linux/amd64
    --mount "type=bind,src=$BUNDLE_DIR,dst=/workspace/offline-bundle"
    --mount "type=bind,src=$socket_path,dst=/var/run/docker.sock"
  )
  local name
  for name in K3S_VERSION K9S_VERSION VLLM_IMAGE CUDA_VALIDATION_IMAGE \
    MODEL_ID MODEL_REVISION HF_TOKEN NVIDIA_DRIVER_BRANCH DRIVER_PACKAGES \
    CTK_PACKAGES DEVICE_PLUGIN_VERSION DEVICE_PLUGIN_IMAGE ARGOCD_VERSION \
    CRANE_VERSION AGENT_IMAGE GIT_MIRROR_IMAGE REGISTRY_IMAGE LOCAL_REGISTRY; do
    printenv "$name" >/dev/null 2>&1 && docker_args+=(--env "$name")
  done

  local image_name
  image_name="ansible-k3s-offline-downloader:$(cksum "$BUNDLE_DIR/Dockerfile.downloader" | awk '{print $1}')"
  if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    echo "Building the downloader image (one-time setup)..."
    docker build --platform linux/amd64 \
      --file "$BUNDLE_DIR/Dockerfile.downloader" \
      --tag "$image_name" "$SCRIPT_DIR"
  fi

  echo "Starting Ubuntu 26.04 AMD64 downloader in Docker..."
  docker "${docker_args[@]}" \
    "$image_name" \
    /workspace/offline-bundle/scripts/download-all-artifacts.sh "$@"
}

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]] \
  || [[ ! -r /etc/os-release ]] \
  || ! grep -qx 'ID=ubuntu' /etc/os-release \
  || ! grep -qx 'VERSION_ID="26.04"' /etc/os-release; then
  run_in_docker "$@"
  exit $?
fi
if [[ ! -r /etc/os-release ]]; then
  echo "Cannot verify the preparation host OS." >&2
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" ]]; then
  echo "Expected Ubuntu 26.04 AMD64; detected ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
  exit 1
fi

for required in apt-get curl docker find python3 sha256sum sort xargs; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "Missing required command: $required" >&2
    exit 1
  }
done
docker info >/dev/null 2>&1 || {
  echo "Docker is installed but its daemon is not available." >&2
  exit 1
}

if [[ "$CLEAN" == "1" && -d "$PAYLOAD_DIR" ]]; then
  if [[ "$ASSUME_YES" != "1" ]]; then
    printf 'Delete and recreate %s? [y/N] ' "$PAYLOAD_DIR"
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || exit 0
  fi
  echo "Removing old generated payload..."
  rm -rf "$PAYLOAD_DIR"
fi
mkdir -p "$PAYLOAD_DIR"
mkdir -p "$STATE_DIR"

steps=(
  download-k3s-artifacts.sh
  download-ansible-debs.sh
  download-gpu-artifacts.sh
  download-operator-tools.sh
  download-argocd-artifacts.sh
  download-observability-artifacts.sh
  download-vllm-artifacts.sh
  download-model-artifacts.sh
)

export DEFER_CHECKSUMS=1
fingerprint_environment="$({
  for name in K3S_VERSION K9S_VERSION VLLM_IMAGE CUDA_VALIDATION_IMAGE \
    MODEL_ID MODEL_REVISION NVIDIA_DRIVER_BRANCH DRIVER_PACKAGES CTK_PACKAGES \
    DEVICE_PLUGIN_VERSION DEVICE_PLUGIN_IMAGE ARGOCD_VERSION CRANE_VERSION \
    AGENT_IMAGE GIT_MIRROR_IMAGE REGISTRY_IMAGE LOCAL_REGISTRY; do
    printf '%s=%s\n' "$name" "${!name-}"
  done
} | sha256sum | cut -d ' ' -f 1)"
total="${#steps[@]}"
for index in "${!steps[@]}"; do
  script="${steps[$index]}"
  marker="$STATE_DIR/$script.complete"
  # A change to one downloader must invalidate only that downloader. The old
  # implementation hashed every internal script into one shared fingerprint,
  # causing an edit to step 8 to rerun steps 1-7 as well.
  fingerprint="$(printf '%s  %s\n%s\n' \
    "$(sha256sum "$INTERNAL_DIR/$script" | cut -d ' ' -f 1)" \
    "$script" "$fingerprint_environment" | sha256sum | cut -d ' ' -f 1)"
  echo
  echo "================================================================"
  printf 'Step %d/%d: %s\n' "$((index + 1))" "$total" "$script"
  echo "================================================================"
  if [[ -f "$marker" ]]; then
    marker_value="$(<"$marker")"
    if [[ "$marker_value" == "v2:$fingerprint" ]]; then
      echo "Already completed; skipping. Use --clean to rebuild."
      continue
    fi
    # Trust and upgrade legacy completion markers once. Existing payloads were
    # produced before per-step fingerprints existed; rerunning them all during
    # this migration would defeat the resume fix.
    if [[ "$marker_value" =~ ^[0-9a-f]{64}$ ]]; then
      printf 'v2:%s\n' "$fingerprint" > "$marker"
      echo "Already completed; migrated resume marker and skipped."
      continue
    fi
  fi
  "$INTERNAL_DIR/$script"
  printf 'v2:%s\n' "$fingerprint" > "$marker"
done
unset DEFER_CHECKSUMS

echo
echo "Generating final checksums (the complete payload is read once)..."
(
  cd "$PAYLOAD_DIR"
  find . -type f ! -name checksums.txt ! -path './.download-state/*' -print0 \
    | sort -z \
    | xargs -0 --no-run-if-empty sha256sum > checksums.txt
)

echo "Verifying the completed payload..."
"$INTERNAL_DIR/verify-artifacts.sh"

echo
echo "Complete offline payload is ready at: $PAYLOAD_DIR"
echo "Copy the entire offline-bundle directory to the isolated host."
