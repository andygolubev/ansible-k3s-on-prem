# Validation Notes

Validated locally:

```bash
bash -n offline-bundle/scripts/download-k3s-artifacts.sh \
  offline-bundle/scripts/download-ansible-debs.sh \
  offline-bundle/scripts/download-gpu-artifacts.sh \
  offline-bundle/scripts/download-vllm-artifacts.sh \
  offline-bundle/scripts/download-model-artifacts.sh \
  offline-bundle/scripts/install-ansible-offline.sh \
  offline-bundle/scripts/verify-artifacts.sh

cd offline-bundle/ansible
ANSIBLE_HOME=../../.ansible-home \
ANSIBLE_LOCAL_TEMP=../../.ansible-tmp \
ansible-playbook --syntax-check -i inventory.ini playbooks/site.yml
```

Payload verification requires a prepared `offline-bundle/payload/` directory. Prepare it on an internet-connected host with Docker:

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace/offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update &&
    apt-get install -y curl ca-certificates &&
    ./scripts/download-k3s-artifacts.sh &&
    ./scripts/download-ansible-debs.sh &&
    ./scripts/download-argocd-artifacts.sh &&
    ./scripts/verify-artifacts.sh
  '
```

Or prepare it on a networked Ubuntu 26.04 AMD64 host:

```bash
cd offline-bundle
./scripts/download-k3s-artifacts.sh
./scripts/download-ansible-debs.sh
./scripts/download-argocd-artifacts.sh
./scripts/verify-artifacts.sh
```

`verify-artifacts.sh` requires real K3s artifacts, Ubuntu 26.04 AMD64 `.deb` packages, GitOps/Argo CD image artifacts, app source folders, and `payload/checksums.txt`.

Validated on an isolated Ubuntu 26.04 AMD64 EC2 target:

```bash
cd "$HOME/ansible-k3s-on-prem/offline-bundle"
./scripts/verify-artifacts.sh
sudo ./scripts/install-ansible-offline.sh

cd "$HOME/ansible-k3s-on-prem/offline-bundle/ansible"
ansible-playbook -i inventory.ini playbooks/site.yml

sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl -n argocd get applications
curl -fsS http://127.0.0.1:5000/v2/
curl -fsS http://127.0.0.1:5000/v2/_catalog
git ls-remote git://127.0.0.1/app-of-apps.git HEAD
sudo systemctl status k3s
```

Expected result: Ansible installs from local `.deb` packages, the K3s/Argo CD playbook completes without internet access, the single node is Ready, core `kube-system` pods are Running or Completed, Argo CD pods are Running, the `agent` Application exists, the local registry responds, and the read-only Git mirror returns refs over `git://`.

## GPU and vLLM Acceptance Criteria

All of the following must pass for the GPU+vLLM deployment to be accepted.

### 1. Server specification

```bash
# Confirm g5.2xlarge on EC2 (check instance metadata)
curl -s http://169.254.169.254/latest/meta-data/instance-type
# Expected: g5.2xlarge

# Confirm root EBS is 200 GiB
lsblk /dev/sda1
# Expected: ~200 GiB device
```

### 2. GPU detected on host

```bash
# Must report NVIDIA A10G
nvidia-smi
# Expected output includes: A10G, driver version, CUDA version

# Full GPU info
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
# Expected: NVIDIA A10G, 24576 MiB, <driver version>
```

### 3. GPU schedulable in Kubernetes

```bash
# Node must advertise nvidia.com/gpu: 1
sudo k3s kubectl describe node | grep -A5 "Allocatable:"
# Expected: nvidia.com/gpu: 1

# Also check via JSON
sudo k3s kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
# Expected: 1
```

### 4. vLLM running without internet access

```bash
# Pod must be in Running state
sudo k3s kubectl -n llm get pods -o wide
# Expected: vllm-* pod in Running state

# Confirm no image pulls from external registries (imagePullPolicy: Never)
sudo k3s kubectl -n llm describe pod -l app=vllm | grep "Image Pull"
# Expected: no pull events; image was loaded from local archive
```

### 5. Qwen model loads from local path

```bash
# Model must exist at the hostPath
ls -la /opt/models/Qwen2.5-7B-Instruct/
# Expected: config.json, tokenizer_config.json, *.safetensors files

# Check vLLM logs for model load (no download attempts)
sudo k3s kubectl -n llm logs deployment/vllm | grep -i "loading\|model\|offline"
# Expected: model loaded from /models/Qwen2.5-7B-Instruct
# Must NOT contain: "downloading", "fetching", "huggingface.co"
```

### 6. vLLM API works

```bash
# Port-forward for local access
sudo k3s kubectl -n llm port-forward svc/vllm 8000:8000 &
sleep 3

# /v1/models must return the Qwen model
curl -fsS http://localhost:8000/v1/models | python3 -m json.tool
# Expected: {"data": [{"id": "Qwen2.5-7B-Instruct", ...}]}

# /v1/chat/completions must return a valid response
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen2.5-7B-Instruct",
    "messages": [{"role": "user", "content": "What is 2+2?"}],
    "max_tokens": 64
  }'
# Expected: {"choices": [{"message": {"content": "4", ...}}], ...}

# Clean up port-forward
kill %1
```

### 7. No external image pulls during offline install

```bash
# Verify no containerd image pull events after bundle load
sudo k3s kubectl get events -A | grep "Pulling\|Failed to pull"
# Expected: no results (or only events from initial setup, not runtime)

# Confirm vllm image was loaded (not pulled)
sudo k3s ctr images list | grep vllm
# Expected: vllm/vllm-openai:v0.8.5 present

sudo k3s ctr images list | grep k8s-device-plugin
# Expected: nvcr.io/nvidia/k8s-device-plugin:v0.17.0 present
```

### 8. All artifacts present with checksums

```bash
cd "$HOME/ansible-k3s-on-prem/offline-bundle"
./scripts/verify-artifacts.sh
# Expected: "Offline bundle artifacts verified." with no errors
```

## Rollback Plan

### Roll back vLLM only (keep GPU support)

```bash
# Delete the llm namespace and all vLLM resources
sudo k3s kubectl delete namespace llm

# Remove the model files (optional — they consume ~15 GB on EBS)
# WARNING: this is destructive; ensure the bundle copy still exists
sudo rm -rf /opt/models/Qwen2.5-7B-Instruct
```

### Roll back GPU support (vLLM + GPU driver + device plugin)

```bash
# 1. Remove vLLM namespace
sudo k3s kubectl delete namespace llm --ignore-not-found

# 2. Remove NVIDIA device plugin
sudo k3s kubectl -n kube-system delete daemonset/nvidia-device-plugin-daemonset --ignore-not-found

# 3. Remove NVIDIA runtime from containerd config and restart K3s
sudo rm -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
sudo systemctl restart k3s

# 4. Uninstall NVIDIA driver and container toolkit (optional)
sudo apt-get remove -y --purge 'nvidia-*' 'libnvidia-*' 'nvidia-container-toolkit' || true
sudo apt-get autoremove -y || true
```

### Roll back to a non-GPU instance type

If rolling back to a t3.* instance:

1. Redeploy the CloudFormation stack with `InstanceType=t3.medium` and `RootVolumeSize=30` (or your preferred size).
2. The new instance will not have a GPU; the GPU install steps in the playbook will fail unless the `gpu_offline` role is removed from `site.yml` for that deployment.
3. No external internet access is required for this rollback — it only affects infrastructure, not software.

> **Note:** Rollback does not require internet access. All software changes are local to the EC2 instance and can be undone by removing packages/manifests from the already-transferred bundle.
