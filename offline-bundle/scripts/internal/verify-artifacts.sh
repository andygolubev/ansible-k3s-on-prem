#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$BUNDLE_DIR/payload"

required_files=(
  "payload/k3s/k3s"
  "payload/k3s/install.sh"
  "payload/k3s/k3s-airgap-images-amd64.tar.zst"
  "payload/gitops/argocd/VERSION"
  "payload/gitops/argocd/install.yaml"
  "payload/gitops/argocd/install-local.yaml"
  "payload/gitops/images/images.tsv"
  "payload/bin/crane"
  "payload/bin/crane.version"
  "payload/checksums.txt"
)

gpu_files=(
  "payload/gpu/debs/nvidia-driver"
  "payload/gpu/debs/nvidia-ctk"
  "payload/gpu/images/nvidia-device-plugin.tar"
  "payload/gpu/device-plugin.yaml"
  "payload/gpu/DEVICE_PLUGIN_VERSION"
  "payload/gpu/DEVICE_PLUGIN_IMAGE"
)

vllm_files=(
  "payload/vllm/images/vllm-openai.tar"
  "payload/vllm/VLLM_IMAGE"
)

operator_tool_files=(
  "payload/tools/k9s/k9s"
  "payload/tools/k9s/VERSION"
  "payload/bin/k9s"
)

observability_files=(
  "payload/observability/VERSIONS.env"
  "payload/observability/manifests/install.yaml"
  "payload/observability/manifests/install-local.yaml"
  "payload/observability/images/images.tsv"
  "payload/observability/images/image-map.tsv"
  "payload/observability/grafana/dashboards/vllm-gpu.json"
)

model_required_files=(
  "config.json"
  "tokenizer_config.json"
)

missing=0
for file in "${required_files[@]}"; do
  if [[ ! -f "$BUNDLE_DIR/$file" ]]; then
    echo "Missing required file: $file" >&2
    missing=1
  fi
done

if [[ -z "$(find "$BUNDLE_DIR/payload/debs/ubuntu-26.04-amd64/ansible-and-deps" -maxdepth 1 -type f -name '*.deb' -print -quit)" ]]; then
  echo "Missing required Ansible .deb packages." >&2
  missing=1
fi

if [[ -f "$BUNDLE_DIR/payload/gitops/images/images.tsv" ]]; then
  while IFS=$'\t' read -r _original _local archive; do
    if [[ -z "${archive:-}" ]]; then
      echo "Malformed image metadata row in payload/gitops/images/images.tsv" >&2
      missing=1
    elif [[ ! -f "$BUNDLE_DIR/$archive" ]]; then
      echo "Missing required image archive: $archive" >&2
      missing=1
    fi
  done < "$BUNDLE_DIR/payload/gitops/images/images.tsv"
fi

if [[ ! -d "$BUNDLE_DIR/gitops/app-of-apps" ]]; then
  echo "Missing versioned app-of-apps source: gitops/app-of-apps" >&2
  missing=1
fi

if [[ ! -d "$BUNDLE_DIR/gitops/agent" ]]; then
  echo "Missing versioned agent source: gitops/agent" >&2
  missing=1
fi

# GPU artifacts (optional — only checked if download-gpu-artifacts.sh has been run)
gpu_missing=0
if [[ -f "$BUNDLE_DIR/payload/gpu/DEVICE_PLUGIN_VERSION" ]]; then
  for f in "${gpu_files[@]}"; do
    if [[ -d "$BUNDLE_DIR/$f" ]]; then
      # directory check: must not be empty of .deb files
      if [[ -z "$(find "$BUNDLE_DIR/$f" -maxdepth 1 -type f -name '*.deb' -print -quit)" ]]; then
        echo "GPU artifact directory is empty (no .deb files): $f" >&2
        gpu_missing=1
      fi
    elif [[ ! -f "$BUNDLE_DIR/$f" ]]; then
      echo "Missing GPU artifact: $f" >&2
      gpu_missing=1
    fi
  done
  if [[ "$gpu_missing" -ne 0 ]]; then
    echo "GPU artifacts incomplete. Run scripts/download-gpu-artifacts.sh first." >&2
    missing=1
  fi
else
  echo "Note: GPU artifacts not found (payload/gpu/DEVICE_PLUGIN_VERSION missing). Run download-gpu-artifacts.sh to include them." >&2
fi

# vLLM artifacts (optional — only checked if download-vllm-artifacts.sh has been run)
if [[ -f "$BUNDLE_DIR/payload/vllm/VLLM_IMAGE" ]]; then
  for f in "${vllm_files[@]}"; do
    if [[ ! -f "$BUNDLE_DIR/$f" ]]; then
      echo "Missing vLLM artifact: $f" >&2
      missing=1
    fi
  done
else
  echo "Note: vLLM artifacts not found (payload/vllm/VLLM_IMAGE missing). Run download-vllm-artifacts.sh to include them." >&2
fi

# Operator tooling artifacts (optional — only checked if download-operator-tools.sh has been run)
if [[ -f "$BUNDLE_DIR/payload/tools/k9s/VERSION" ]]; then
  for f in "${operator_tool_files[@]}"; do
    if [[ ! -f "$BUNDLE_DIR/$f" ]]; then
      echo "Missing operator tooling artifact: $f" >&2
      missing=1
    fi
  done
else
  echo "Note: Operator tooling artifacts not found (payload/tools/k9s/VERSION missing). Run download-operator-tools.sh to include k9s." >&2
fi

# Observability artifacts (optional — only checked if download-observability-artifacts.sh has been run)
if [[ -f "$BUNDLE_DIR/payload/observability/VERSIONS.env" ]]; then
  for f in "${observability_files[@]}"; do
    if [[ ! -f "$BUNDLE_DIR/$f" ]]; then
      echo "Missing observability artifact: $f" >&2
      missing=1
    fi
  done
  if [[ -f "$BUNDLE_DIR/payload/observability/images/images.tsv" ]]; then
    while IFS=$'\t' read -r _original _local archive; do
      if [[ -z "${archive:-}" ]]; then
        echo "Malformed image metadata row in payload/observability/images/images.tsv" >&2
        missing=1
      elif [[ ! -f "$BUNDLE_DIR/$archive" ]]; then
        echo "Missing observability image archive: $archive" >&2
        missing=1
      fi
    done < "$BUNDLE_DIR/payload/observability/images/images.tsv"
  fi
else
  echo "Note: Observability artifacts not found (payload/observability/VERSIONS.env missing). Run download-observability-artifacts.sh to include them." >&2
fi

# Model artifacts (optional — only checked if download-model-artifacts.sh has been run)
MODEL_SNAPSHOT_DIR="$BUNDLE_DIR/payload/models/Qwen2.5-7B-Instruct"
if [[ -d "$MODEL_SNAPSHOT_DIR" ]]; then
  for f in "${model_required_files[@]}"; do
    if [[ ! -f "$MODEL_SNAPSHOT_DIR/$f" ]]; then
      echo "Missing model file in payload/models/Qwen2.5-7B-Instruct/: $f" >&2
      missing=1
    fi
  done
  if [[ -z "$(find "$MODEL_SNAPSHOT_DIR" -maxdepth 2 -type f -name '*.safetensors' -print -quit)" ]] && \
     [[ -z "$(find "$MODEL_SNAPSHOT_DIR" -maxdepth 2 -type f -name '*.bin' -print -quit)" ]]; then
    echo "No model weight files (.safetensors or .bin) found in $MODEL_SNAPSHOT_DIR" >&2
    missing=1
  fi
else
  echo "Note: Model snapshot not found (payload/models/Qwen2.5-7B-Instruct/ missing). Run download-model-artifacts.sh to include it." >&2
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

if [[ ! -s "$PAYLOAD_DIR/checksums.txt" ]]; then
  echo "payload/checksums.txt is empty. Run the download scripts first." >&2
  exit 1
fi

(
  cd "$PAYLOAD_DIR"
  sha256sum --check checksums.txt
)

if [[ ! -x "$BUNDLE_DIR/payload/k3s/k3s" ]]; then
  echo "K3s binary is not executable." >&2
  exit 1
fi

if [[ ! -x "$BUNDLE_DIR/payload/k3s/install.sh" ]]; then
  echo "K3s install script is not executable." >&2
  exit 1
fi

if [[ ! -x "$BUNDLE_DIR/payload/bin/crane" ]]; then
  echo "crane binary is not executable." >&2
  exit 1
fi

if [[ -f "$BUNDLE_DIR/payload/bin/k9s" && ! -x "$BUNDLE_DIR/payload/bin/k9s" ]]; then
  echo "k9s binary is not executable." >&2
  exit 1
fi

echo "Offline bundle artifacts verified."
