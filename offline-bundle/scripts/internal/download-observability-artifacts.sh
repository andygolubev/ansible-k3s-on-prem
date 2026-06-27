#!/usr/bin/env bash
# Downloads and prepares observability artifacts for offline installation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
OBS_SRC_DIR="$BUNDLE_DIR/observability"
OBS_DIR="$PAYLOAD_DIR/observability"
MANIFESTS_DIR="$OBS_DIR/manifests"
IMAGES_DIR="$OBS_DIR/images"
DASHBOARDS_DIR="$OBS_DIR/grafana/dashboards"
LOCAL_REGISTRY="${LOCAL_REGISTRY:-localhost:5000}"

usage() {
  cat <<'USAGE'
Usage: download-observability-artifacts.sh

Packages pinned Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector,
kube-state-metrics, node-exporter, NVIDIA DCGM exporter, Grafana datasources,
and dashboards for offline installation.

Environment:
  LOCAL_REGISTRY   local registry prefix used in rendered manifests
                   (default: localhost:5000)
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

sanitize_image() {
  printf '%s' "$1" | sed -E 's#[/:@]+#_#g; s#[^A-Za-z0-9_.-]#_#g'
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

archive_image() {
  local original="$1"
  local local_image="$2"
  local archive_name="$3"
  local archive_path="$IMAGES_DIR/$archive_name"

  echo "Pulling $original"
  docker pull --platform linux/amd64 "$original"
  docker tag "$original" "$local_image"
  docker save "$original" "$local_image" -o "$archive_path"
  printf '%s\t%s\t%s\n' "$original" "$local_image" "payload/observability/images/$archive_name" >> "$IMAGES_DIR/images.tsv"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

require_command docker
require_command python3
require_command sha256sum

if [[ ! -f "$OBS_SRC_DIR/VERSIONS.env" ]]; then
  echo "Missing observability version file: $OBS_SRC_DIR/VERSIONS.env" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$OBS_SRC_DIR/VERSIONS.env"

images=(
  "$PROMETHEUS_IMAGE"
  "$GRAFANA_IMAGE"
  "$LOKI_IMAGE"
  "$PROMTAIL_IMAGE"
  "$TEMPO_IMAGE"
  "$OTEL_COLLECTOR_IMAGE"
  "$KUBE_STATE_METRICS_IMAGE"
  "$NODE_EXPORTER_IMAGE"
  "$DCGM_EXPORTER_IMAGE"
)

mkdir -p "$MANIFESTS_DIR" "$IMAGES_DIR" "$DASHBOARDS_DIR"
: > "$IMAGES_DIR/images.tsv"
: > "$IMAGES_DIR/image-map.tsv"

cp "$OBS_SRC_DIR/VERSIONS.env" "$OBS_DIR/VERSIONS.env"
cp "$OBS_SRC_DIR/manifests/install.yaml" "$MANIFESTS_DIR/install.yaml"
cp "$OBS_SRC_DIR/grafana/dashboards/"*.json "$DASHBOARDS_DIR/"
cp "$MANIFESTS_DIR/install.yaml" "$MANIFESTS_DIR/install-local.yaml"

for image in "${images[@]}"; do
  archive_name="$(sanitize_image "$image").tar"
  local_image="$LOCAL_REGISTRY/$image"
  archive_image "$image" "$local_image" "$archive_name"
  printf '%s\t%s\n' "$image" "$local_image" >> "$IMAGES_DIR/image-map.tsv"
  python3 - "$MANIFESTS_DIR/install-local.yaml" "$image" "$local_image" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(path.read_text().replace(sys.argv[2], sys.argv[3]))
PY
done

generate_checksums

echo "Downloaded observability artifacts to $OBS_DIR"
echo "Updated $PAYLOAD_DIR/checksums.txt"
