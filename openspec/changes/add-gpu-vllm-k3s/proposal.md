## Why

The current offline bundle provisions a single-node, CPU-only K3s server sized for a small demo (`t3.*`), and the existing GitOps agent app only references a placeholder "local VLLM-compatible endpoint" that does not yet exist. To run a real LLM workload behind the chatbot, the deployment must move to a GPU instance and gain a fully offline, GPU-accelerated vLLM serving stack. This change provides that VLLM endpoint that the prior `add-argocd-agent-gitops` change deferred.

## What Changes

- Re-target the infrastructure to AWS EC2 `g5.2xlarge` (1× NVIDIA A10G 24 GB, 8 vCPU, 32 GiB RAM, 1× ~450 GB ephemeral NVMe instance store) with a 200 GB gp3 root EBS volume, replacing the `t3.*` defaults in the CloudFormation template.
- Add a documented storage layout that splits persistent data (EBS root) from large ephemeral caches (NVMe instance store), including NVMe mount steps and explicit data-loss warnings.
- Add offline NVIDIA GPU enablement for K3s: host driver packages, NVIDIA container toolkit/runtime wiring for containerd, the NVIDIA device plugin, and a GPU validation flow (`nvidia-smi` on host and inside a `nvidia.com/gpu: 1` test pod).
- Add Kubernetes manifests to serve `Qwen/Qwen2.5-7B-Instruct` with the vLLM OpenAI-compatible API server, configured for GPU execution and conservative single-node co-tenancy (`--dtype float16`, `--max-model-len 4096`, `--gpu-memory-utilization 0.85`, 1 replica, low concurrency), loading the model from a preloaded local path with no runtime internet access.
- Extend the offline bundle (download scripts, payload layout, verification, Ansible install) with all new GPU and vLLM artifacts: driver/toolkit `.deb` packages, device-plugin manifest+image, vLLM/CUDA container images, the Qwen model snapshot (weights, tokenizer, config), Kubernetes manifests, and SHA256 checksums.
- Add optional vLLM observability (Prometheus scrape/ServiceMonitor for vLLM metrics, plus a documented set of GPU/latency/throughput metrics to watch).
- Update offline runtime guarantees, validation commands, acceptance criteria, and a rollback plan so installation and inference happen with no pulls from Docker Hub, GHCR, Hugging Face, NVIDIA repos, PyPI, or apt/yum.

## Capabilities

### New Capabilities
- `gpu-instance-provisioning`: Covers the `g5.2xlarge` server specification, 200 GB gp3 root EBS, the ephemeral NVMe instance store, and the persistent-vs-ephemeral storage layout (mounting, path placement, data-loss warnings).
- `k3s-gpu-runtime`: Covers offline NVIDIA host driver install, container toolkit/runtime configuration for K3s containerd, the NVIDIA device plugin, and GPU scheduling validation.
- `vllm-model-serving`: Covers the offline vLLM Kubernetes deployment for `Qwen/Qwen2.5-7B-Instruct` (namespace, Deployment, Service, optional Ingress, probes, resource requests/limits, local model mount, vLLM args, OpenAI-compatible API usage) and its optional Prometheus observability.

### Modified Capabilities
- None. (`openspec/specs/` contains no published specs yet; the related `add-argocd-agent-gitops` change is still in-flight and is not modified here.)

## Impact

- Affected infrastructure: `cloudformation-ec2-ssh-only.yaml` (instance type, root EBS size/type, NVMe handling).
- Affected offline bundle: `offline-bundle/scripts/` (new GPU + vLLM + model download/verify scripts), `offline-bundle/ansible/` (new GPU and vLLM roles, group_vars, `site.yml`), `offline-bundle/README-offline.md`, and `offline-bundle/VALIDATION.md`.
- New generated payload under `offline-bundle/payload/` for NVIDIA `.deb` packages, device-plugin/vLLM/CUDA images, the Qwen model snapshot, and Kubernetes manifests.
- New runtime dependencies: NVIDIA A10G driver + container toolkit on the host; vLLM and CUDA base images loaded into containerd; large local model cache placed before first boot.
- Operational change: target node now requires GPU drivers and ephemeral NVMe management; no target-side internet access is allowed during install or inference.
- Out of scope: multi-node/multi-GPU scaling, model quantization beyond float16, autoscaling, and serving models other than the selected Qwen model.
