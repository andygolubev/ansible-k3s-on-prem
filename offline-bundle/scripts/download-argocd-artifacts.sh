#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BUNDLE_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
GITOPS_DIR="$PAYLOAD_DIR/gitops"
ARGOCD_DIR="$GITOPS_DIR/argocd"
IMAGES_DIR="$GITOPS_DIR/images"
BIN_DIR="$PAYLOAD_DIR/bin"

ARGOCD_VERSION=""
REGISTRY_IMAGE="${REGISTRY_IMAGE:-registry:2}"
GIT_MIRROR_IMAGE="${GIT_MIRROR_IMAGE:-nginx:1.27-alpine}"
AGENT_IMAGE="${AGENT_IMAGE:-agent-chatbot:0.1.0}"
LOCAL_REGISTRY="${LOCAL_REGISTRY:-localhost:5000}"
CRANE_VERSION="${CRANE_VERSION:-v0.21.6}"
ARGOCD_LATEST_URL="${ARGOCD_LATEST_URL:-https://github.com/argoproj/argo-cd/releases/latest}"

usage() {
  cat <<'USAGE'
Usage: download-argocd-artifacts.sh [--argocd-version VERSION]

Downloads and packages Argo CD, local registry, Git mirror, and agent images
for offline installation.

Environment overrides:
  REGISTRY_IMAGE     default registry:2
  GIT_MIRROR_IMAGE   default nginx:1.27-alpine
  AGENT_IMAGE        default agent-chatbot:0.1.0
  LOCAL_REGISTRY     default localhost:5000
  CRANE_VERSION      default v0.21.6
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --argocd-version)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --argocd-version" >&2
        exit 1
      fi
      ARGOCD_VERSION="$2"
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
require_command docker
require_command python3
require_command sha256sum
require_command tar

mkdir -p "$ARGOCD_DIR" "$IMAGES_DIR" "$BIN_DIR"

if [[ -z "$ARGOCD_VERSION" ]]; then
  ARGOCD_VERSION="$(
    python3 - "$ARGOCD_LATEST_URL" <<'PY'
import sys
from urllib.request import Request, urlopen

req = Request(sys.argv[1], method="HEAD")
with urlopen(req, timeout=30) as response:
    url = response.geturl().rstrip("/")
print(url.rsplit("/", 1)[-1])
PY
  )"
fi

if [[ ! "$ARGOCD_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "Resolved Argo CD version does not look like a release tag: $ARGOCD_VERSION" >&2
  exit 1
fi

echo "$ARGOCD_VERSION" > "$ARGOCD_DIR/VERSION"
curl -fL "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
  -o "$ARGOCD_DIR/install.yaml"

ARGOCD_IMAGES_FILE="$ARGOCD_DIR/images.txt"
python3 - "$ARGOCD_DIR/install.yaml" > "$ARGOCD_IMAGES_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
images = []
for match in re.finditer(r"(?m)^\s*image:\s*[\"']?([^\"'\s]+)[\"']?\s*$", text):
    image = match.group(1)
    if image not in images:
        images.append(image)
for image in images:
    print(image)
PY

LOCAL_INSTALL="$ARGOCD_DIR/install-local.yaml"
cp "$ARGOCD_DIR/install.yaml" "$LOCAL_INSTALL"

sanitize_image() {
  printf '%s' "$1" | sed -E 's#[/:@]+#_#g; s#[^A-Za-z0-9_.-]#_#g'
}

archive_image() {
  local original="$1"
  local local_image="$2"
  local archive_name="$3"
  local archive_path="$IMAGES_DIR/$archive_name"

  echo "Pulling $original"
  docker pull --platform linux/amd64 "$original"
  docker tag "$original" "$local_image"
  docker save "$original" "$local_image" -o "$archive_path"
  printf '%s\t%s\t%s\n' "$original" "$local_image" "payload/gitops/images/$archive_name" >> "$IMAGES_DIR/images.tsv"
}

: > "$IMAGES_DIR/images.tsv"

crane_archive="$(mktemp)"
trap 'rm -f "$crane_archive"' EXIT
curl -fL "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
  -o "$crane_archive"
tar -xzf "$crane_archive" -C "$BIN_DIR" crane
chmod 0755 "$BIN_DIR/crane"
echo "$CRANE_VERSION" > "$BIN_DIR/crane.version"

while IFS= read -r image; do
  if [[ -z "$image" ]]; then
    continue
  fi
  local_image="$LOCAL_REGISTRY/$image"
  archive_name="$(sanitize_image "$image").tar"
  archive_image "$image" "$local_image" "$archive_name"
  python3 - "$LOCAL_INSTALL" "$image" "$local_image" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(path.read_text().replace(sys.argv[2], sys.argv[3]))
PY
done < "$ARGOCD_IMAGES_FILE"

archive_image "$REGISTRY_IMAGE" "$LOCAL_REGISTRY/$REGISTRY_IMAGE" "$(sanitize_image "$REGISTRY_IMAGE").tar"
archive_image "$GIT_MIRROR_IMAGE" "$LOCAL_REGISTRY/$GIT_MIRROR_IMAGE" "$(sanitize_image "$GIT_MIRROR_IMAGE").tar"

echo "Building $AGENT_IMAGE"
docker build --platform linux/amd64 -t "$AGENT_IMAGE" "$REPO_ROOT/apps/agent"
docker tag "$AGENT_IMAGE" "$LOCAL_REGISTRY/$AGENT_IMAGE"
docker save "$AGENT_IMAGE" "$LOCAL_REGISTRY/$AGENT_IMAGE" -o "$IMAGES_DIR/$(sanitize_image "$AGENT_IMAGE").tar"
printf '%s\t%s\t%s\n' "$AGENT_IMAGE" "$LOCAL_REGISTRY/$AGENT_IMAGE" "payload/gitops/images/$(sanitize_image "$AGENT_IMAGE").tar" >> "$IMAGES_DIR/images.tsv"

(
  cd "$PAYLOAD_DIR"
  find . -type f ! -name checksums.txt -print0 \
    | sort -z \
    | xargs -0 --no-run-if-empty sha256sum > checksums.txt
)

echo "Downloaded Argo CD $ARGOCD_VERSION and wrote offline GitOps payload to $GITOPS_DIR"
