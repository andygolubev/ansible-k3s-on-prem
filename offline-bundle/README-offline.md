# Offline Single-Node K3s Bundle

This bundle installs a single-node K3s server on an isolated Ubuntu 26.04 AMD64 host, such as a UTM VM or EC2 instance.

Ansible runs inside the target host and targets `localhost` with `ansible_connection=local`. Docker is not required on the target, and SSH is only needed if you use SCP or remote shell access to transfer and run the bundle.

## Supported Environment

- Preparation host: Linux AMD64 with Docker, or macOS with Docker Desktop (Intel or Apple Silicon)
- Target host: Ubuntu 26.04 LTS AMD64 (e.g. EC2 `g5.2xlarge`)
- Cluster: single-node K3s server with NVIDIA A10G GPU
- Network during install: isolated, no internet access

## Payload Directory

All downloaded/generated, non-versioned offline files live under:

```text
offline-bundle/payload/
```

This directory is ignored by git. It contains only artifacts fetched or built
by the preparation scripts; source-controlled installers, Ansible, manifests,
GitOps definitions, and application source stay outside `payload/` directly
under `offline-bundle/`. You can delete `payload/` and regenerate it with the
download scripts.

### Download everything with one command

The recommended preparation path is the aggregate downloader. Docker must be
running and at least 50 GB must be free. On macOS and non-AMD64 hosts, the
script automatically launches an **Ubuntu 26.04 AMD64** Docker container and
mounts the bundle and the active Docker socket:

```bash
cd offline-bundle
./scripts/download-all-artifacts.sh
```

To discard the current generated payload and rebuild it completely:

```bash
./scripts/download-all-artifacts.sh --clean
```

It invokes all specialized downloaders in order, hashes the complete payload
only once at the end, and runs `verify-artifacts.sh`. The individual scripts
below remain useful for refreshing one artifact group. `payload/` is generated
and gitignored; do not place version-controlled source or manifests there.
Successful steps are recorded under `payload/.download-state/`, so an
interrupted run resumes at the first incomplete step. Downloader changes or
version overrides invalidate the markers; `--clean` forces a complete rebuild.

Generated payload layout:

```text
payload/
  k3s/                              K3s binary, install script, airgap image tarball
  debs/ubuntu-26.04-amd64/
    ansible-and-deps/               Ansible + dependency .deb packages
  gitops/
    argocd/                         Argo CD install manifest (original + local-image variant)
    images/                         images.tsv manifest + image archives (.tar)
  tools/
    k9s/                             k9s binary and VERSION metadata
  observability/
    VERSIONS.env                     pinned observability component versions
    manifests/                       observability install manifest (original + local-image variant)
    images/                          images.tsv, image-map.tsv, and image archives (.tar)
    grafana/dashboards/              vLLM/GPU dashboard JSON
  gpu/
    debs/nvidia-driver/             NVIDIA driver .deb packages + deps
    debs/nvidia-ctk/                NVIDIA container toolkit .deb packages + deps
    images/nvidia-device-plugin.tar Device plugin image archive
    device-plugin.yaml              Device plugin Kubernetes manifest
    DEVICE_PLUGIN_VERSION
    DEVICE_PLUGIN_IMAGE
  vllm/
    images/vllm-openai.tar          vLLM server image archive (~8 GB compressed)
    images/cuda-validation.tar      CUDA image for offline GPU validation
    VLLM_IMAGE
    CUDA_VALIDATION_IMAGE
  models/
    Qwen2.5-7B-Instruct/            Model weights, tokenizer, config (~14 GB)
  bin/                              crane binary
  checksums.txt                     SHA256 checksums for all files
```

## Prepare Payload With Docker

All scripts can be run from macOS or Linux with Docker Desktop/Engine installed. No Linux VM is required.

Each script group has different requirements, so they are run in separate steps:

**Step 1 — k3s + Ansible debs** (needs Ubuntu 26.04 for apt; no Docker socket required):

```bash
# From repo root
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace/offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update -qq &&
    apt-get install -y --no-install-recommends curl ca-certificates python3 sudo &&
    ./scripts/internal/download-k3s-artifacts.sh &&
    ./scripts/internal/download-ansible-debs.sh
  '
```

**Step 2 — Argo CD + agent image** (needs Docker; runs directly on the prep host):

```bash
cd offline-bundle
./scripts/internal/download-argocd-artifacts.sh
```

**Step 3 — NVIDIA GPU packages + device plugin image** (needs Ubuntu 26.04 for apt AND Docker socket for image pull):

```bash
# From repo root
docker run --rm \
  --platform linux/amd64 \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$PWD:/workspace" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /workspace/offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update -qq &&
    apt-get install -y --no-install-recommends docker.io curl ca-certificates gpg python3 &&
    ./scripts/internal/download-gpu-artifacts.sh &&
    chown -R "${HOST_UID}:${HOST_GID}" payload/gpu
  '
```

**Step 4 — vLLM image** (needs Docker; runs directly on the prep host):

```bash
cd offline-bundle
./scripts/internal/download-vllm-artifacts.sh
```

**Step 5 — Qwen2.5-7B-Instruct model** (needs Python 3; runs directly on the prep host):

```bash
cd offline-bundle
./scripts/internal/download-model-artifacts.sh
```

**Step 6 — operator tools** (needs curl/tar; runs directly on the prep host):

```bash
cd offline-bundle
./scripts/internal/download-operator-tools.sh
```

**Step 7 — observability stack** (needs Docker; runs directly on the prep host):

```bash
cd offline-bundle
./scripts/internal/download-observability-artifacts.sh
```

**Step 8 — Verify everything**:

```bash
cd offline-bundle
./scripts/internal/verify-artifacts.sh
```

## Prepare Payload On Linux

On a networked Ubuntu 26.04 AMD64 host with Docker installed:

```bash
cd offline-bundle

# K3s, Ansible debs, Argo CD
./scripts/internal/download-k3s-artifacts.sh
./scripts/internal/download-ansible-debs.sh
./scripts/internal/download-argocd-artifacts.sh

# GPU packages + device plugin (Ubuntu 26.04 + Docker required)
sudo ./scripts/internal/download-gpu-artifacts.sh

# vLLM image (Docker required, ~20 GB download)
./scripts/internal/download-vllm-artifacts.sh

# Qwen2.5-7B-Instruct model (~15 GB download)
./scripts/internal/download-model-artifacts.sh

# Operator tools and observability (Docker required for observability images)
./scripts/internal/download-operator-tools.sh
./scripts/internal/download-observability-artifacts.sh

# Verify everything
./scripts/internal/verify-artifacts.sh
```

`download-k3s-artifacts.sh` follows the K3s GitHub releases page and downloads the latest release at execution time. The K3s binary and air-gap image tarball always use the same resolved version:

- `payload/k3s/k3s`
- `payload/k3s/install.sh`
- `payload/k3s/k3s-airgap-images-amd64.tar.zst`
- `payload/k3s/VERSION`

The download URL follows the official K3s air-gap form, for example:

```bash
curl -L -o k3s-airgap-images-amd64.tar.zst \
  "https://github.com/k3s-io/k3s/releases/download/v1.33.3%2Bk3s1/k3s-airgap-images-amd64.tar.zst"
```

`download-ansible-debs.sh` downloads Ubuntu 26.04 AMD64 packages for local Ansible execution into:

```text
payload/debs/ubuntu-26.04-amd64/ansible-and-deps/
```

The default package set intentionally does not include `openssh-server`.

`download-argocd-artifacts.sh` downloads a pinned Argo CD install manifest, rewrites image references for `localhost:5000`, downloads the offline `crane` registry push helper, builds the `agent` image, and saves all required Argo CD, registry, and agent image archives into:

```text
payload/gitops/
```

The default local registry is `localhost:5000`. Override image defaults with `REGISTRY_IMAGE`, `GIT_MIRROR_IMAGE`, `AGENT_IMAGE`, or `LOCAL_REGISTRY`.

`download-operator-tools.sh` downloads a pinned Linux AMD64 `k9s` binary into:

```text
payload/tools/k9s/
payload/bin/k9s
```

Override the version with `K9S_VERSION` or `--k9s-version`.

`download-observability-artifacts.sh` copies the checked-in observability manifests and Grafana dashboard, pulls pinned images, saves image archives, rewrites the local install manifest for `localhost:5000`, and writes metadata into:

```text
payload/observability/
```

The pinned component versions are listed in `offline-bundle/observability/VERSIONS.env`. The default stack includes Prometheus, Grafana, Loki, Promtail, Tempo, OpenTelemetry Collector, kube-state-metrics, node-exporter, and NVIDIA DCGM exporter.

All download scripts regenerate:

```text
payload/checksums.txt
```

If K3s version resolution fails, rerun with verbose output:

```bash
VERBOSE=1 ./scripts/internal/download-k3s-artifacts.sh
```

## Copy Bundle To The Target

After `payload/` has been prepared, copy only the complete `offline-bundle/`
directory to the target. It is self-contained: versioned GitOps sources are in
`offline-bundle/gitops/`, while downloaded artifacts are in
`offline-bundle/payload/`.

Preferred transfer options:

1. UTM shared directory.
2. An ISO image containing `offline-bundle/`.
3. SCP, if SSH access is available on the target.

Example once the bundle is visible on the target:

```bash
cp -a /path/to/offline-bundle "$HOME/offline-bundle"
cd "$HOME/offline-bundle"
```

## Install Everything With One Command

From the copied `offline-bundle/` directory on the isolated target, run:

```bash
./install.sh
```

The installer elevates with `sudo`, performs host and free-space preflight
checks, verifies every generated payload artifact, bootstraps Ansible from
local `.deb` files, runs the complete playbook with verbose task output, and
prints final node and pod status. It is safe to rerun after correcting a
failure.

The individual verification, bootstrap, and playbook commands below are kept
for troubleshooting and advanced operation; they are not required during the
normal one-command flow.

## Optional Isolation Check

Before installation, confirm the target cannot reach the internet:

```bash
curl https://github.com
```

This should fail in the isolated target environment.

## Verify Local Payload Offline

Inside the target:

```bash
cd "$HOME/ansible-k3s-on-prem/offline-bundle"
./scripts/internal/verify-artifacts.sh
```

This checks required files, executable bits for K3s scripts, and `payload/checksums.txt`.

## Bootstrap Ansible Offline

Ansible cannot install itself through Ansible. Run the one shell bootstrap step:

```bash
cd "$HOME/ansible-k3s-on-prem/offline-bundle"
sudo ./scripts/internal/install-ansible-offline.sh
```

The bootstrap script installs only local `.deb` packages from:

```text
payload/debs/ubuntu-26.04-amd64/ansible-and-deps/
```

It uses:

```bash
apt-get install -f -y --no-download
```

If dependencies are missing from the payload, the command fails instead of downloading from the internet.

## Install K3s With Local Ansible

Run the bundled playbook:

```bash
cd "$HOME/ansible-k3s-on-prem/offline-bundle/ansible"
ansible-playbook -i inventory.ini playbooks/site.yml
```

The playbook copies local payload artifacts into place and runs the installer with `INSTALL_K3S_SKIP_DOWNLOAD=true`.

The `k3s_offline` role also creates `/var/lib/rancher/k3s/agent/images/.cache.json` by default. This enables K3s conditional image imports for supported releases, avoiding re-importing unchanged air-gap image archives on every K3s restart. Set `k3s_enable_conditional_image_import: false` in `ansible/group_vars/all.yml` to disable it.

The `argocd_offline` role then imports prepared image archives, starts a single-node local registry at `localhost:5000`, pushes prepared images into it with bundled `crane`, creates read-only local Git mirrors from `offline-bundle/gitops/app-of-apps/` and `offline-bundle/gitops/agent/`, exposes them through a host-side `git daemon` and in-cluster Service, applies the local-image Argo CD manifests, and applies the root app-of-apps Application.

The `operator_tools_offline` role installs `k9s` to `/usr/local/bin/k9s`.

The `observability_offline` role imports and pushes prepared observability images, creates the Grafana dashboard ConfigMap, applies the local observability manifest, and waits for Prometheus, Grafana, Loki, Promtail, Tempo, OpenTelemetry Collector, kube-state-metrics, node-exporter, and DCGM exporter. The stack is intentionally single-node with bounded `emptyDir` storage for proof-of-concept operation.

## Agent App Configuration

The `gitops/agent/chart/values.yaml` file controls the sample LangChain chatbot deployment:

- `replicaCount`: defaults to `1` for the offline demo.
- `vllm.baseUrl`: OpenAI-compatible local endpoint.
- `vllm.model`: model name sent to the endpoint.
- `vllm.apiKey`: API key value for the OpenAI-compatible client.
- `langfuse.host`, `langfuse.publicKey`, `langfuse.secretKey`: optional Langfuse tracing settings.
- `tracing.tempo.enabled`: enables OpenTelemetry trace export to the in-cluster collector.
- `tracing.tempo.endpoint`: OTLP endpoint. Default: `otel-collector.observability.svc.cluster.local:4317`.
- `tracing.tempo.serviceName`: OpenTelemetry service name.

When Langfuse settings are empty, Langfuse tracing is disabled and the app still starts. Tempo tracing is separate and does not require external services.

## Storage Layout (g5.2xlarge)

The `g5.2xlarge` instance has two storage devices:

| Device | Type | Size | Purpose |
|--------|------|------|---------|
| `/dev/sda1` (root EBS) | Persistent gp3 | 200 GiB | OS, K3s config, persistent data, canonical model copy |
| `/dev/nvme1n1` (instance store) | **Ephemeral** NVMe | ~450 GiB | Container image cache, model working cache, temp inference data |

**EBS root (persistent):**
```
/                        OS, K3s binaries and config
/var/lib/rancher/k3s/    K3s state (etcd, certificates, containerd metadata)
/opt/models/             Canonical offline model copy — the source of truth
```

**NVMe instance store (ephemeral):**
```
/mnt/nvme/               NVMe mount point
/mnt/nvme/containerd/    Large container layer cache (symlinked from K3s path)
/mnt/nvme/model-cache/   HuggingFace / vLLM model working cache
```

> **WARNING — DATA LOSS RISK:** The NVMe instance store is ephemeral. Its contents are **permanently lost** when the EC2 instance is stopped, rebooted after a hardware failure, or terminated. Never store your only copy of any data on the NVMe. The canonical model copy must remain on the EBS root volume at `/opt/models/`.

### Preparing the NVMe Instance Store

Run the following on the target before the Ansible playbook (or let the `gpu_offline` role handle it automatically):

```bash
NVME_DEV=/dev/nvme1n1
NVME_MOUNT=/mnt/nvme

# Confirm the device exists
lsblk "$NVME_DEV"

# Format (first use only — this destroys existing data)
mkfs.ext4 -F "$NVME_DEV"

# Mount
mkdir -p "$NVME_MOUNT"
mount "$NVME_DEV" "$NVME_MOUNT"

# Persist across reboots (note: instance store is reformatted on stop/start — this only survives reboot)
echo "$NVME_DEV  $NVME_MOUNT  ext4  defaults,nofail  0  2" >> /etc/fstab
```

> **Note:** The `gpu_offline` Ansible role performs this setup automatically and creates the working directories under `/mnt/nvme/`.

## GPU Support (g5.2xlarge / NVIDIA A10G)

The offline bundle includes GPU enablement artifacts downloaded by `download-gpu-artifacts.sh`:

```text
payload/gpu/
  debs/nvidia-driver/        NVIDIA driver .deb packages (Ubuntu 26.04 amd64)
  debs/nvidia-ctk/           NVIDIA container toolkit .deb packages
  images/                    NVIDIA device plugin image archive (.tar)
  device-plugin.yaml         NVIDIA device plugin manifest
  DEVICE_PLUGIN_VERSION      Device plugin version file
```

The `gpu_offline` Ansible role installs the driver and toolkit from local `.deb` packages (no external apt access), configures the NVIDIA runtime for K3s containerd, deploys the device plugin, and validates that the node can schedule GPU pods.

## vLLM Model Serving

The offline bundle includes vLLM artifacts downloaded by `download-vllm-artifacts.sh` and `download-model-artifacts.sh`:

```text
payload/vllm/
  images/                    vLLM image archive (.tar)
  VLLM_IMAGE                 vLLM image reference file
payload/models/
  Qwen2.5-7B-Instruct/       Model weights, tokenizer, config, HF snapshot metadata
```

Kubernetes manifests are in `offline-bundle/ansible/roles/vllm_offline/files/`:

```text
namespace.yaml               llm namespace
deployment.yaml              vLLM Deployment (1 replica, GPU, offline args)
service.yaml                 ClusterIP Service on port 8000
servicemonitor.yaml          Optional Prometheus ServiceMonitor
```

The vLLM server exposes an OpenAI-compatible API on port 8000:

```bash
# Check served models
curl http://vllm.llm.svc.cluster.local:8000/v1/models

# Chat completion (run from within the cluster or via kubectl port-forward)
kubectl -n llm port-forward svc/vllm 8000:8000 &
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen2.5-7B-Instruct",
    "messages": [{"role": "user", "content": "Hello, what can you do?"}],
    "max_tokens": 256
  }'
```

## Single-Node Assumptions

The offline GitOps bootstrap is designed for the current single-node K3s target:

- The registry is exposed as `localhost:5000` on the node and is suitable for local containerd pulls.
- The Git mirror is read-only, generated from copied source folders during bootstrap, and exposed with the `git://` protocol for Argo CD.
- The target needs 200 GiB gp3 root EBS for the payload, K3s state, registry storage, and canonical model copy.
- Multi-node registry distribution, persistent Git hosting, and multi-GPU deployments are outside this workflow.

## Verify No Internet Access Is Required

Before and after installation, confirm the target has no outbound internet access:

```bash
# Should fail on an isolated target
curl --max-time 5 https://registry-1.docker.io/v2/ && echo "INTERNET REACHABLE - NOT ISOLATED" || echo "No internet access confirmed"
curl --max-time 5 https://huggingface.co && echo "HF REACHABLE - NOT ISOLATED" || echo "No HuggingFace access confirmed"

# Monitor for unexpected outbound connections during install
ss -tnp | grep -v "127.0.0.1\|::1"
```

During and after the playbook, no image pulls should occur from external registries. All images are loaded from local archives and the vLLM model is read from the local `/opt/models/` path.

## Observability: GPU and vLLM Metrics

The bundle now includes an offline observability stack in the `observability` namespace:

- Prometheus for Kubernetes, node, GPU, and vLLM metrics.
- Grafana with Prometheus, Loki, and Tempo datasources.
- Loki and Promtail for workload logs.
- Tempo and OpenTelemetry Collector for traces.
- kube-state-metrics, node-exporter, and NVIDIA DCGM exporter.

The Prometheus config statically scrapes vLLM at `vllm.llm.svc.cluster.local:8000` and also honors `prometheus.io/scrape` pod annotations. The existing vLLM ServiceMonitor remains optional for future Prometheus Operator deployments; this stack does not require the ServiceMonitor CRD.

Access Grafana from the target:

```bash
sudo k3s kubectl -n observability port-forward svc/grafana 3000:3000
```

Then open `http://localhost:3000`. The default local credentials are `admin` / `admin`; anonymous viewer access is enabled for the offline demo.

Access Prometheus, Loki, or Tempo APIs:

```bash
sudo k3s kubectl -n observability port-forward svc/prometheus 9090:9090
sudo k3s kubectl -n observability port-forward svc/loki 3100:3100
sudo k3s kubectl -n observability port-forward svc/tempo 3200:3200
```

The installed Grafana dashboard is `vLLM GPU Operations`.

Key metrics and queries to monitor in Grafana or Prometheus:

| Metric | Source | Alert threshold |
|--------|--------|----------------|
| `DCGM_FI_DEV_GPU_UTIL` | DCGM exporter | <10% for >5 min (idle) |
| `DCGM_FI_DEV_FB_USED` | DCGM exporter | >22 GiB (OOM risk) |
| `vllm:request_success_total` | vLLM `/metrics` | Track request rate |
| `vllm:e2e_request_latency_seconds` | vLLM `/metrics` | p99 > 30s (overloaded) |
| `vllm:num_requests_running` | vLLM `/metrics` | Concurrency level |
| `kube_pod_container_status_restarts_total` | kube-state-metrics | >0 (crashes) |

Useful Loki queries:

```text
{namespace="llm", app="vllm"}
{namespace="agent", app_kubernetes_io_name="agent"}
```

Tempo traces are emitted by the agent through `otel-collector.observability.svc.cluster.local:4317` when `tracing.tempo.enabled=true`.

Pod OOM kills:
```bash
sudo k3s kubectl get events -n llm --field-selector reason=OOMKilling
```

## Operator Tooling

`k9s` is installed at `/usr/local/bin/k9s` by the `operator_tools_offline` role. Use the K3s kubeconfig:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml k9s
```

Noninteractive validation:

```bash
k9s version --short
```

## Observability Rollback

Rollback removes the observability stack and k9s without changing K3s, Argo CD, vLLM, or the agent application:

```bash
# Remove observability workloads and telemetry storage.
sudo k3s kubectl delete namespace observability --ignore-not-found

# Remove k9s from the target host.
sudo rm -f /usr/local/bin/k9s
```

To keep observability disabled on the next playbook run, remove or comment out `operator_tools_offline` and `observability_offline` in `offline-bundle/ansible/playbooks/site.yml` before running Ansible again.

## Final Verification

After the playbook completes:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl -n argocd get applications
curl -fsS http://127.0.0.1:5000/v2/
git ls-remote git://127.0.0.1/app-of-apps.git HEAD
sudo systemctl status k3s
```

Expected result: one Ready K3s server node, running core `kube-system` pods, running Argo CD pods, an `agent` Application registered in Argo CD, and a reachable local registry.

For GPU + vLLM additional checks:

```bash
# GPU on host
nvidia-smi

# GPU schedulable
sudo k3s kubectl describe node | grep -A5 "nvidia.com/gpu"

# vLLM running
sudo k3s kubectl -n llm get pods -o wide
sudo k3s kubectl -n llm get svc

# vLLM API
sudo k3s kubectl -n llm port-forward svc/vllm 8000:8000 &
curl -fsS http://localhost:8000/v1/models
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"ping"}],"max_tokens":16}'
```
