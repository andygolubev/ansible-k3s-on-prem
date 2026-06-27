#!/usr/bin/env bash
# Downloads the vLLM and CUDA validation images for offline installation.
# Runs on any internet-connected host with Docker available (Linux, macOS).
#
# Downloads:
#   payload/vllm/images/vllm-openai.tar    vLLM OpenAI-compatible server image archive
#   payload/vllm/images/cuda-validation.tar CUDA image used by the GPU validation pod
#   payload/vllm/VLLM_IMAGE                Full image reference used (for Ansible)
#   payload/vllm/CUDA_VALIDATION_IMAGE     Full validation image reference
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
VLLM_DIR="$PAYLOAD_DIR/vllm"
IMAGES_DIR="$VLLM_DIR/images"

# vLLM v0.8.5 ships with CUDA 12.4 runtime; no separate CUDA base image needed.
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:v0.8.5}"
CUDA_VALIDATION_IMAGE="${CUDA_VALIDATION_IMAGE:-nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04}"

usage() {
  cat <<'USAGE'
Usage: download-vllm-artifacts.sh

Downloads the vLLM server and CUDA GPU-validation images for offline use.
Runs on any internet-connected host with Docker available (Linux, macOS).

Environment:
  VLLM_IMAGE    Full image reference to pull (default: vllm/vllm-openai:v0.8.5)
  CUDA_VALIDATION_IMAGE
                Validation image (default: nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04)

Note: The vLLM image is several GB. Ensure you have sufficient disk space.
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

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

require_command docker
require_command sha256sum

mkdir -p "$IMAGES_DIR"

echo "Pulling vLLM image: $VLLM_IMAGE"
echo "Warning: this image is several GB and may take a while to download."
docker pull --platform linux/amd64 "$VLLM_IMAGE"

ARCHIVE="$IMAGES_DIR/vllm-openai.tar"
echo "Saving image to $ARCHIVE..."
docker save "$VLLM_IMAGE" -o "$ARCHIVE"
echo "$VLLM_IMAGE" > "$VLLM_DIR/VLLM_IMAGE"

echo "Pulling CUDA validation image: $CUDA_VALIDATION_IMAGE"
docker pull --platform linux/amd64 "$CUDA_VALIDATION_IMAGE"
CUDA_VALIDATION_ARCHIVE="$IMAGES_DIR/cuda-validation.tar"
echo "Saving image to $CUDA_VALIDATION_ARCHIVE..."
docker save "$CUDA_VALIDATION_IMAGE" -o "$CUDA_VALIDATION_ARCHIVE"
echo "$CUDA_VALIDATION_IMAGE" > "$VLLM_DIR/CUDA_VALIDATION_IMAGE"

generate_checksums

echo ""
echo "vLLM image saved to $ARCHIVE"
echo "Image reference: $VLLM_IMAGE"
echo "CUDA validation image: $CUDA_VALIDATION_IMAGE"
echo "Updated $PAYLOAD_DIR/checksums.txt"
