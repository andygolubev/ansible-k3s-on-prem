## Context

The repo provisions a single-node, air-gapped K3s server from an offline bundle: a networked "prep" host runs `offline-bundle/scripts/download-*.sh` to fetch and pin artifacts into `offline-bundle/payload/`, which is verified by `verify-artifacts.sh` and then installed on the isolated target by `offline-bundle/ansible` (`playbooks/site.yml` + roles `bootstrap_ansible`, `k3s_offline`, `argocd_offline`). The current target is a CPU-only `t3.*` instance, and the in-flight `add-argocd-agent-gitops` change deploys a LangChain agent that calls a not-yet-existent "local VLLM endpoint".

This change supplies that endpoint and upgrades the host to GPU. Hard constraints carried over from the existing design: no target-side internet access during install or runtime; pinned tags/digests only (no `latest`); images loaded into K3s/containerd from local archives; every artifact verified by SHA256. The target OS is Ubuntu 26.04 amd64.

## Goals / Non-Goals

**Goals:**
- Re-target infrastructure to `g5.2xlarge` with 200 GB gp3 root EBS and a documented ephemeral-NVMe layout.
- Enable NVIDIA GPU on K3s fully offline: host driver, container toolkit/runtime for containerd, device plugin, and a GPU validation flow.
- Serve `Qwen/Qwen2.5-7B-Instruct` with vLLM (OpenAI-compatible, GPU, conservative single-node config) from a preloaded local model directory.
- Extend the download/verify/install/observability flow to cover all new artifacts, with checksums and a rollback path.

**Non-Goals:**
- Multi-node or multi-GPU scaling, autoscaling, request batching tuning beyond conservative defaults.
- Quantization beyond `float16`, or serving models other than the selected Qwen model.
- Replacing the existing Argo CD/GitOps mechanism; vLLM may be delivered as plain manifests applied directly (see Decisions).

## Decisions

**1. Plain Kubernetes YAML for vLLM over a Helm chart.** The project's implementation guidance prefers simple explicit YAML, and the existing K3s/argocd install applies raw manifests. vLLM is a single Deployment + Service (+ optional ServiceMonitor); a chart adds indirection without benefit. Manifests live under the offline payload and are applied by a new Ansible role. *Alternative considered:* a Helm chart like the `agent` app uses — rejected as overkill for one workload and harder to pin offline.

**2. NVIDIA device plugin via static manifest, not GPU Operator.** The GPU Operator pulls many images and assumes online driver management, which conflicts with the air-gapped constraint. Installing the host driver from `.deb` packages + the container toolkit + a pinned device-plugin manifest is smaller and fully offline-controllable. *Alternative considered:* NVIDIA GPU Operator — rejected for air-gap complexity and image sprawl.

**3. Host driver from distro/NVIDIA `.deb` packages, mirroring the existing `download-ansible-debs.sh` pattern.** A new `download-gpu-artifacts.sh` collects the driver, container toolkit, and their dependency `.deb`s for Ubuntu 26.04 amd64 into `payload/debs/` (or a `payload/gpu/` subtree), and a new `gpu_offline` Ansible role installs them with apt pointed only at the local files. This keeps GPU enablement consistent with how Ansible itself is already bootstrapped offline.

**4. Containerd NVIDIA runtime wired through K3s config.d.** K3s manages its own containerd; the role drops an NVIDIA runtime into K3s's containerd template (`config.toml.tmpl`) or uses the toolkit's containerd configuration so the `nvidia` runtime class is available, then restarts K3s. The device plugin's pod and vLLM run under that runtime.

**5. Canonical model copy on EBS, working cache on NVMe.** The full Qwen snapshot is shipped in the bundle and placed on the EBS root (persistent). A documented setup step copies/links it to the vLLM model path. The NVMe instance store is mounted for the container image cache and any large regenerable caches. vLLM mounts the local model directory read-only via a hostPath/PV so the pod never downloads. *Rationale:* NVMe is ephemeral (lost on stop/start); persistent data must survive on EBS.

**6. Conservative vLLM config for co-tenancy.** `--dtype float16`, `--max-model-len 4096`, `--gpu-memory-utilization 0.85`, 1 replica, low concurrency — chosen to leave A10G headroom and keep the node stable while Prometheus/Grafana/Langfuse/Postgres/etc. share it. Pinned vLLM image tag/digest matching the bundle.

**7. Observability is optional and additive.** A ServiceMonitor/scrape config for vLLM's `/metrics` is included but gated on a Prometheus stack being present, so the core serving path has no hard dependency on monitoring.

## Risks / Trade-offs

- **A10G 24 GB VRAM pressure with a 7B fp16 model + KV cache** → keep `max-model-len 4096` and `gpu-memory-utilization 0.85`; document lowering these if OOM/KV-cache errors appear; monitor GPU memory and OOM kills.
- **Driver/kernel mismatch on Ubuntu 26.04 (driver built for a kernel the AMI later updates)** → pin the AMI/kernel, ship matching driver `.deb`s, and validate `nvidia-smi` on the host before proceeding; document re-running the driver step if the kernel changes.
- **Large offline bundle (multi-GB model + CUDA/vLLM images)** → ship the model snapshot and image archives separately, verify by SHA256, and place the model on EBS; document transfer size expectations.
- **Ephemeral NVMe surprises (operator stores persistent data on NVMe)** → explicit data-loss warnings in docs and storage spec; canonical copies live on EBS only.
- **GPU not advertised (`nvidia.com/gpu` allocatable = 0) due to runtime misconfig** → the GPU validation step (host `nvidia-smi`, device-plugin readiness, `nvidia.com/gpu: 1` test pod) gates vLLM deployment so failures surface early.
- **vLLM image expecting a CUDA runtime not present offline** → ship the required CUDA/runtime base images in the bundle and load them into containerd before applying manifests.

## Migration Plan

1. On the networked prep host, run the new GPU/vLLM/model download scripts; verify all artifacts (`verify-artifacts.sh`) by SHA256.
2. Deploy the updated CloudFormation (`g5.2xlarge`, 200 GB gp3 root) and transfer the bundle to the target.
3. Mount NVMe, install NVIDIA driver + container toolkit, configure containerd runtime, deploy device plugin, run GPU validation.
4. Load vLLM/CUDA images into containerd, place the model on EBS into the model path, apply `llm` namespace + vLLM manifests, wait for readiness, validate `/v1/models` and `/v1/chat/completions`.

**Rollback:** vLLM and GPU layers are additive. To roll back: `kubectl delete` the `llm` namespace and device plugin, optionally remove the NVIDIA runtime from containerd and uninstall driver/toolkit packages, and redeploy the prior CloudFormation instance type if needed. The base K3s + Argo CD install is unaffected. Because nothing was pulled from the internet, rollback requires no external access.

## Open Questions

- Exact NVIDIA driver branch and CUDA version to pin for the Ubuntu 26.04 AMI kernel (resolve during the GPU download step against the actual AMI).
- Whether the project's Prometheus stack will be present at vLLM install time (determines if the ServiceMonitor is applied now or documented for later).
- Whether to expose vLLM via Ingress — only if/when the project adopts an ingress controller; default is internal Service only.
