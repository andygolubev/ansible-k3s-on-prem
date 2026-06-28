#!/usr/bin/env bash
# Downloads NVIDIA GPU support artifacts for offline installation on Ubuntu 26.04 AMD64.
# Must run on an internet-connected Ubuntu 26.04 AMD64 host (or Docker container with
# Docker socket mounted for image operations).
#
# Downloads:
#   payload/gpu/debs/nvidia-driver/    NVIDIA driver .deb packages + deps
#   payload/gpu/debs/nvidia-ctk/       NVIDIA container toolkit .deb packages + deps
#   payload/gpu/images/                NVIDIA device plugin image archive
#   payload/gpu/device-plugin.yaml     NVIDIA device plugin manifest
#   payload/gpu/DEVICE_PLUGIN_VERSION  Device plugin version file
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
GPU_DIR="$PAYLOAD_DIR/gpu"
DRIVER_DEB_DIR="$GPU_DIR/debs/nvidia-driver"
CTK_DEB_DIR="$GPU_DIR/debs/nvidia-ctk"
IMAGES_DIR="$GPU_DIR/images"

NVIDIA_DRIVER_BRANCH="${NVIDIA_DRIVER_BRANCH:-580}"
NVIDIA_KERNEL_FLAVOUR="${NVIDIA_KERNEL_FLAVOUR:-aws}"
DEVICE_PLUGIN_VERSION="${DEVICE_PLUGIN_VERSION:-v0.17.0}"
DEVICE_PLUGIN_IMAGE="${DEVICE_PLUGIN_IMAGE:-nvcr.io/nvidia/k8s-device-plugin:${DEVICE_PLUGIN_VERSION}}"
DEVICE_PLUGIN_MANIFEST_URL="${DEVICE_PLUGIN_MANIFEST_URL:-https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${DEVICE_PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml}"

usage() {
  cat <<'USAGE'
Usage: download-gpu-artifacts.sh [--driver-branch BRANCH] [--device-plugin-version VERSION]

Downloads NVIDIA GPU support artifacts for offline installation.
Must run on an internet-connected Ubuntu 26.04 AMD64 host.
Requires: apt-get, docker (for image download), curl, sha256sum.

Options:
  --driver-branch BRANCH         NVIDIA driver branch to install (default: 580)
  --device-plugin-version VER    NVIDIA device plugin version (default: v0.17.0)

Environment:
  NVIDIA_DRIVER_BRANCH     Same as --driver-branch
  DEVICE_PLUGIN_VERSION    Same as --device-plugin-version
  DEVICE_PLUGIN_IMAGE      Full device plugin image ref (default: nvcr.io/nvidia/k8s-device-plugin:VERSION)
USAGE
}

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
    echo "This script must run on Ubuntu 26.04 AMD64." >&2
    echo "Detected: ID=${ID:-unknown} VERSION_ID=${VERSION_ID:-unknown}" >&2
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

restore_payload_ownership() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER" "$PAYLOAD_DIR"
  fi
}

download_deb_packages() {
  local dest_dir="$1"
  shift
  local packages=("$@")
  local package
  local -a filtered

  # A resumed bundle build must not retain packages selected by an older
  # dependency graph. dpkg installs every file in this directory on the target.
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  echo "Resolving packages and dependencies for: ${packages[*]}"
  mapfile -t resolved < <(
    apt-cache depends --recurse \
      --no-recommends \
      --no-suggests \
      --no-conflicts \
      --no-breaks \
      --no-replaces \
      --no-enhances \
      "${packages[@]}" \
      | awk '
          /^[[:alnum:]][[:alnum:].+:-]*$/ { print $1; next }
          /^[[:space:]]*(PreDepends|Depends):/ { print $2 }
        ' \
      | sed 's/:any$//' \
      | grep -E '^[[:alnum:]][[:alnum:].+-]+$' \
      | sort -u
  )

  filtered=()
  for package in "${resolved[@]}"; do
    case "$package" in
      opensysusers|systemd-standalone-sysusers)
        continue
        ;;
    esac
    filtered+=("$package")
  done
  resolved=("${filtered[@]}")

  if [[ "${#resolved[@]}" -eq 0 ]]; then
    echo "No packages resolved for: ${packages[*]}" >&2
    exit 1
  fi

  echo "Downloading ${#resolved[@]} packages to $dest_dir..."
  (
    cd "$dest_dir"
    apt-get download "${resolved[@]}"
  )

  if [[ -z "$(find "$dest_dir" -maxdepth 1 -type f -name '*.deb' -print -quit)" ]]; then
    echo "No .deb packages were downloaded to $dest_dir" >&2
    exit 1
  fi
}

download_driver_packages() {
  local dest_dir="$1"
  shift
  local packages=("$@")
  local package
  local -a resolved filtered

  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  echo "Resolving AWS NVIDIA driver packages for: ${packages[*]}"
  mapfile -t resolved < <(
    apt-cache depends --recurse \
      --no-recommends --no-suggests --no-conflicts --no-breaks \
      --no-replaces --no-enhances "${packages[@]}" \
      | awk '
          /^[[:alnum:]][[:alnum:].+:-]*$/ { print $1; next }
          /^[[:space:]]*(PreDepends|Depends):/ { print $2 }
        ' \
      | sed 's/:any$//' \
      | grep -E '^[[:alnum:]][[:alnum:].+-]+$' \
      | sort -u
  )

  filtered=()
  for package in "${resolved[@]}"; do
    case "$package" in
      opensysusers|systemd-standalone-sysusers|make-guile)
        # Full systemd supplies systemd-sysusers; standalone alternatives
        # conflict when every payload package is passed to dpkg together.
        # Likewise, make-guile conflicts with the regular make dependency.
        continue
        ;;
      nvidia-dkms-*)
        # The AWS kernel module package is used instead of DKMS.
        continue
        ;;
      linux-image-*|linux-headers-*|linux-main-modules-*|linux-modules-*|linux-objects-*|linux-signatures-*)
        # apt-cache recursively emits every alternative kernel flavour. Keep
        # only NVIDIA module dependencies for the selected target flavour.
        if [[ "$package" != *nvidia* || "$package" != *"${NVIDIA_KERNEL_FLAVOUR}"* ]]; then
          continue
        fi
        ;;
    esac
    filtered+=("$package")
  done

  if [[ " ${filtered[*]} " != *" linux-modules-nvidia-${NVIDIA_DRIVER_BRANCH}-server-${NVIDIA_KERNEL_FLAVOUR} "* ]]; then
    echo "Failed to resolve the NVIDIA ${NVIDIA_KERNEL_FLAVOUR} kernel module package." >&2
    exit 1
  fi

  echo "Downloading ${#filtered[@]} AWS driver packages to $dest_dir..."
  (
    cd "$dest_dir"
    apt-get download "${filtered[@]}"
  )
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver-branch)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --driver-branch" >&2; exit 1
      fi
      NVIDIA_DRIVER_BRANCH="$2"; shift 2 ;;
    --device-plugin-version)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --device-plugin-version" >&2; exit 1
      fi
      DEVICE_PLUGIN_VERSION="$2"
      DEVICE_PLUGIN_IMAGE="nvcr.io/nvidia/k8s-device-plugin:${DEVICE_PLUGIN_VERSION}"
      DEVICE_PLUGIN_MANIFEST_URL="https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${DEVICE_PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml"
      shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_linux_amd64
require_ubuntu_2604
require_command apt-get
require_command apt-cache
require_command curl
require_command docker
require_command gpg
require_command sha256sum

mkdir -p "$DRIVER_DEB_DIR" "$CTK_DEB_DIR" "$IMAGES_DIR"

# ---------------------------------------------------------------------------
# NVIDIA CUDA apt repository (provides driver packages)
# ---------------------------------------------------------------------------
echo "Adding NVIDIA CUDA apt repository for Ubuntu 26.04..."
CUDA_KEYRING_DEB="$GPU_DIR/cuda-keyring.deb"
curl -fL "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/cuda-keyring_1.1-1_all.deb" \
  -o "$CUDA_KEYRING_DEB"
as_root dpkg -i "$CUDA_KEYRING_DEB"
rm -f "$CUDA_KEYRING_DEB"

# ---------------------------------------------------------------------------
# NVIDIA Container Toolkit apt repository
# ---------------------------------------------------------------------------
echo "Adding NVIDIA Container Toolkit apt repository..."
KEYRING_DIR=/usr/share/keyrings
CTK_KEYRING="$KEYRING_DIR/nvidia-container-toolkit-keyring.gpg"

as_root bash -c "
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o '$CTK_KEYRING'
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=$CTK_KEYRING] https://#' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
"

as_root apt-get update

# ---------------------------------------------------------------------------
# Download NVIDIA driver packages
# ---------------------------------------------------------------------------
echo "Downloading NVIDIA driver ${NVIDIA_DRIVER_BRANCH} packages..."
DRIVER_PACKAGES=(
  "nvidia-driver-${NVIDIA_DRIVER_BRANCH}-server"
  "nvidia-utils-${NVIDIA_DRIVER_BRANCH}-server"
  "libnvidia-compute-${NVIDIA_DRIVER_BRANCH}-server"
  "linux-modules-nvidia-${NVIDIA_DRIVER_BRANCH}-server-${NVIDIA_KERNEL_FLAVOUR}"
)
download_driver_packages "$DRIVER_DEB_DIR" "${DRIVER_PACKAGES[@]}"

# ---------------------------------------------------------------------------
# Download NVIDIA container toolkit packages
# ---------------------------------------------------------------------------
echo "Downloading NVIDIA container toolkit packages..."
CTK_PACKAGES=(nvidia-container-toolkit)
download_deb_packages "$CTK_DEB_DIR" "${CTK_PACKAGES[@]}"

# ---------------------------------------------------------------------------
# Download NVIDIA device plugin image
# ---------------------------------------------------------------------------
echo "Pulling NVIDIA device plugin image: $DEVICE_PLUGIN_IMAGE"
docker pull --platform linux/amd64 "$DEVICE_PLUGIN_IMAGE"
DEVICE_PLUGIN_ARCHIVE="$IMAGES_DIR/nvidia-device-plugin.tar"
docker save "$DEVICE_PLUGIN_IMAGE" -o "$DEVICE_PLUGIN_ARCHIVE"
echo "$DEVICE_PLUGIN_IMAGE" > "$GPU_DIR/DEVICE_PLUGIN_IMAGE"

# ---------------------------------------------------------------------------
# Download NVIDIA device plugin manifest
# ---------------------------------------------------------------------------
echo "Downloading NVIDIA device plugin manifest (${DEVICE_PLUGIN_VERSION})..."
curl -fL "$DEVICE_PLUGIN_MANIFEST_URL" -o "$GPU_DIR/device-plugin.yaml"
echo "$DEVICE_PLUGIN_VERSION" > "$GPU_DIR/DEVICE_PLUGIN_VERSION"

# ---------------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------------
generate_checksums
restore_payload_ownership

echo ""
echo "NVIDIA GPU artifacts downloaded to $GPU_DIR"
echo "  Driver branch:       ${NVIDIA_DRIVER_BRANCH}"
echo "  Device plugin:       ${DEVICE_PLUGIN_VERSION}"
echo "  Image archive:       ${DEVICE_PLUGIN_ARCHIVE}"
echo "Updated $PAYLOAD_DIR/checksums.txt"
