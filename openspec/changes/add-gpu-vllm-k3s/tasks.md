## 1. Infrastructure: g5.2xlarge + storage

- [x] 1.1 Update `cloudformation-ec2-ssh-only.yaml` to default `InstanceType` to `g5.2xlarge` and add it (and other `g5.*`) to `AllowedValues`.
- [x] 1.2 Set the root EBS volume to 200 GB `gp3` via a `BlockDeviceMappings` block on the instance resource.
- [x] 1.3 Document the storage layout (EBS = OS/K3s/persistent/backups/canonical model; NVMe = image cache/model cache/temp) in `offline-bundle/README-offline.md`, with explicit ephemeral-NVMe data-loss warnings.
- [x] 1.4 Add documented NVMe setup steps/script: detect the instance-store device, format, and mount it at the documented mountpoint (e.g. `/mnt/nvme`), and place container image cache and/or model cache there.

## 2. Offline download: GPU + vLLM + model artifacts

- [x] 2.1 Add `offline-bundle/scripts/download-gpu-artifacts.sh` to fetch NVIDIA driver `.deb`s, container toolkit `.deb`s and their dependencies for Ubuntu 26.04 amd64, plus the device-plugin manifest and image, into the payload.
- [x] 2.2 Add `offline-bundle/scripts/download-vllm-artifacts.sh` to pull and save the pinned vLLM image and any required CUDA/runtime base images as local archives.
- [x] 2.3 Add `offline-bundle/scripts/download-model-artifacts.sh` to download the full `Qwen/Qwen2.5-7B-Instruct` snapshot (weights, tokenizer, config, snapshot metadata) into the payload model directory.
- [x] 2.4 Generate SHA256 checksums for all new GPU, image, and model artifacts and record them alongside existing checksums.
- [x] 2.5 Extend `offline-bundle/scripts/verify-artifacts.sh` to verify presence + checksums of the GPU packages, device-plugin manifest/image, vLLM/CUDA images, and the model snapshot.

## 3. K3s GPU enablement (Ansible)

- [x] 3.1 Create a `gpu_offline` Ansible role that installs the NVIDIA driver and container toolkit from local `.deb`s only (apt pointed at local files, no external repos).
- [x] 3.2 Configure the NVIDIA runtime in K3s containerd (config template / containerd config) and restart K3s so the `nvidia` runtime is active.
- [x] 3.3 Load the device-plugin (and CUDA/vLLM) images into K3s/containerd from local archives.
- [x] 3.4 Apply the NVIDIA device plugin manifest so the node advertises `nvidia.com/gpu`.
- [x] 3.5 Add GPU validation tasks: `nvidia-smi` on host, device-plugin Ready, a `nvidia.com/gpu: 1` test pod running `nvidia-smi` successfully; fail the play if any check fails.
- [x] 3.6 Wire the `gpu_offline` role into `offline-bundle/ansible/playbooks/site.yml` (after `k3s_offline`, before vLLM) and add required `group_vars/all.yml` variables.

## 4. vLLM Kubernetes manifests

- [x] 4.1 Create the `llm` Namespace manifest.
- [x] 4.2 Create the vLLM Deployment: 1 replica, pinned image tag/digest, request+limit `nvidia.com/gpu: 1`, conservative CPU/memory requests, args `--model /models/Qwen2.5-7B-Instruct --dtype float16 --max-model-len 4096 --gpu-memory-utilization 0.85`, HF offline env vars, and readiness/liveness probes against the API server.
- [x] 4.3 Mount the preloaded local model directory into the pod (hostPath/PV, read-only) and configure the HF cache path for offline loading.
- [x] 4.4 Create the Service exposing port 8000 internally; add an Ingress only if the project already uses ingress (otherwise omit).
- [x] 4.5 Add a model-placement script/step that copies the bundle model snapshot into the canonical EBS model path and links/copies it to the vLLM mount path.
- [x] 4.6 Create a `vllm_offline` Ansible role that loads vLLM/CUDA images, places the model, and applies the `llm` manifests; wire it into `site.yml`.

## 5. Observability (optional)

- [x] 5.1 Add a vLLM ServiceMonitor or Prometheus scrape config for `/metrics`, gated on the Prometheus stack being present.
- [x] 5.2 Document the metrics to watch (GPU utilization, GPU memory, request latency, token throughput, pod restarts, OOM kills) and minimal dashboard notes in `README-offline.md`.

## 6. Offline runtime guarantees + docs

- [x] 6.1 Ensure all manifests reference pinned tags/digests matching the bundle (no `latest`) and either local registry or containerd-loaded images.
- [x] 6.2 Document how to verify no internet access is required (e.g. block egress, run install + inference, confirm success).
- [x] 6.3 Add an example `curl` for `/v1/chat/completions` and a `/v1/models` check to the docs.

## 7. Validation, acceptance, rollback

- [x] 7.1 Update `offline-bundle/VALIDATION.md` with GPU and vLLM validation commands (host `nvidia-smi`, GPU test pod, `nvidia.com/gpu` allocatable, `/v1/models`, `/v1/chat/completions`).
- [x] 7.2 Verify acceptance criteria end-to-end: g5.2xlarge + 200 GB gp3, GPU detected, GPU pods schedulable, vLLM starts offline, Qwen loads from local path, `/v1/models` + `/v1/chat/completions` work, no image pulls during install, all artifacts present with checksums.
- [x] 7.3 Document the rollback plan (delete `llm` namespace + device plugin, optionally remove NVIDIA runtime/driver, redeploy prior instance type) confirming no external access is needed.
