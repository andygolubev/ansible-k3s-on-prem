#!/usr/bin/env bash
# Downloads the Qwen2.5-7B-Instruct model snapshot from Hugging Face for offline use.
# Must run on an internet-connected Linux AMD64 host with Python 3 and pip available.
#
# Downloads:
#   payload/models/Qwen2.5-7B-Instruct/   Full model snapshot (weights, tokenizer, config)
#
# The model is downloaded via huggingface_hub. Set HF_TOKEN if the model requires
# authentication (Qwen2.5-7B-Instruct is a public model and does not require a token).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"
MODELS_DIR="$PAYLOAD_DIR/models"

MODEL_ID="${MODEL_ID:-Qwen/Qwen2.5-7B-Instruct}"
MODEL_REVISION="${MODEL_REVISION:-main}"
HF_TOKEN="${HF_TOKEN:-}"
PYTHON="${PYTHON:-python3}"

usage() {
  cat <<'USAGE'
Usage: download-model-artifacts.sh [--model MODEL_ID] [--revision REV]

Downloads a Hugging Face model snapshot for offline vLLM use.
Requires: python3, pip (installs huggingface_hub if needed).

Options:
  --model MODEL_ID    HF model repo ID (default: Qwen/Qwen2.5-7B-Instruct)
  --revision REV      Git revision / branch (default: main)

Environment:
  HF_TOKEN     Hugging Face access token (not needed for public models)
  MODEL_ID     Same as --model
  MODEL_REVISION  Same as --revision

Note: Qwen2.5-7B-Instruct weights are ~15 GB. Ensure sufficient disk space.
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
    --model)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --model" >&2; exit 1
      fi
      MODEL_ID="$2"; shift 2 ;;
    --revision)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --revision" >&2; exit 1
      fi
      MODEL_REVISION="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_command "$PYTHON"
require_command sha256sum

# Ensure huggingface_hub is available
if ! "$PYTHON" -c "import huggingface_hub" 2>/dev/null; then
  echo "Installing huggingface_hub..."
  "$PYTHON" -m pip install --quiet "huggingface_hub[cli]>=0.26"
fi

# Derive local directory name from model ID (repo name only)
MODEL_NAME="${MODEL_ID##*/}"
MODEL_DEST="$MODELS_DIR/$MODEL_NAME"

mkdir -p "$MODELS_DIR"

echo "Downloading model snapshot: $MODEL_ID (revision: $MODEL_REVISION)"
echo "Destination: $MODEL_DEST"
echo "Warning: model weights are ~15 GB. This may take a while."

"$PYTHON" - <<PYEOF
import os
import sys
from huggingface_hub import snapshot_download

token = os.environ.get("HF_TOKEN") or None
model_id = "${MODEL_ID}"
revision = "${MODEL_REVISION}"
dest = "${MODEL_DEST}"

print(f"Downloading {model_id}@{revision} to {dest}", flush=True)

snapshot_download(
    repo_id=model_id,
    revision=revision,
    local_dir=dest,
    local_dir_use_symlinks=False,
    token=token,
    ignore_patterns=["*.msgpack", "*.h5", "flax_model*", "tf_model*", "rust_model*"],
)
print(f"Download complete: {dest}", flush=True)
PYEOF

if [[ ! -d "$MODEL_DEST" ]]; then
  echo "Model directory was not created: $MODEL_DEST" >&2
  exit 1
fi

# Quick sanity check: ensure config.json and tokenizer files exist
for required in config.json tokenizer_config.json; do
  if [[ ! -f "$MODEL_DEST/$required" ]]; then
    echo "WARNING: expected file missing in model snapshot: $required" >&2
  fi
done

generate_checksums

echo ""
echo "Model snapshot saved to: $MODEL_DEST"
echo "Updated $PAYLOAD_DIR/checksums.txt"
echo ""
echo "To install on the offline target, the Ansible vllm_offline role"
echo "copies this directory to /opt/models/$MODEL_NAME on the EBS root."
