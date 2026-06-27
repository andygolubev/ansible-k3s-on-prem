# EC2 Testing Handoff Log

Last updated: 2026-06-27 (Asia/Jerusalem)

## Current status

The K3s Flannel/CNI failure is fixed. The confirmed cause was the custom NVIDIA
containerd `config.toml.tmpl`: it replaced K3s defaults and directed containerd
to `/etc/cni/net.d` and `/opt/cni/bin`. K3s actually keeps its CNI configuration
and binaries below `/var/lib/rancher/k3s/`. The nftables warning was unrelated.

The repaired installation has passed these live checks on the EC2 test VM:

- K3s node is `Ready`; `RuntimeReady` and `NetworkReady` are true.
- `crictl info` reports the K3s CNI paths and `lastCNILoadStatus: OK`.
- `cni0` exists; CoreDNS, metrics-server, and Traefik are ready.
- K3s auto-detects `/usr/bin/nvidia-container-runtime`; RuntimeClass `nvidia`
  exists while ordinary workloads continue to use `runc`.
- NVIDIA device plugin advertises one `nvidia.com/gpu` (A10G).
- The offline CUDA validation pod completed and `nvidia-smi` saw the A10G.
- vLLM serves `/v1/models`; a chat completion returned `offline GPU works`.
- A cold VM reboot preserved all readiness and GPU checks.
- NVMe filesystem UUID before and after reboot was unchanged:
  `0cf83ab7-e611-4e16-a627-1ed962786934`.

A final full `install.sh` rerun/idempotence test completed successfully after
the reboot: `failed=0`, all workloads healthy, and the NVMe UUID unchanged.

## Implemented repair

- Removed the obsolete tracked NVIDIA containerd template and remove stale
  deployed copies from existing hosts.
- Removed `nvidia-ctk runtime configure`; it configures system containerd, not
  K3s containerd.
- Verify `/usr/bin/nvidia-container-runtime`, restart K3s after toolkit or
  stale-template changes, then validate effective CNI/runtime readiness.
- Added a node/CNI readiness gate before device-plugin and GPU-capacity checks.
- Set `runtimeClassName: nvidia` on the device plugin, CUDA validation pod, and
  vLLM; default runtime remains `runc`.
- Added a pinned CUDA validation image to the generated offline payload flow.
- Made vLLM use `Recreate` for a single GPU and set `VLLM_PORT=29500` to avoid
  collision with Kubernetes's injected `VLLM_PORT` service URI.
- On reruns, skip the standalone validation pod when the existing vLLM
  deployment already claims the single GPU.
- Run the vLLM health probe inside the pod instead of probing an unforwarded
  host-local port.
- Preserved earlier nouveau handling, NVIDIA driver reuse, and NVMe
  no-reformat idempotency fixes.

## Connect to the test VM

From the repository root:

```bash
cd /Users/andy/repo/andygolubev/ansible-k3s-on-prem
chmod 400 .aws/k3s-on-prem.pem
ssh -i .aws/k3s-on-prem.pem \
  ubuntu@ec2-18-134-164-108.eu-west-2.compute.amazonaws.com
```

- Region: `eu-west-2`
- Stack: `k3s-on-prem`
- Instance: `i-06eb140d78dae846d` (`g5.2xlarge`, NVIDIA A10G)
- Public IP: `18.134.164.108`
- Bundle: `/home/ubuntu/offline-bundle`

SSH is restricted to the CIDR configured by the CloudFormation `SshCidr`
parameter. If the PEM is missing, retrieve it from SSM parameter
`/ec2/keypair/key-058c8a8511730e2b2` in `eu-west-2`; never commit the key.

## Operate and verify

Do not run two installers concurrently.

```bash
# Is an installer still active?
pgrep -af 'install.sh|ansible-playbook|verify-artifacts' || true

# Run or resume the isolated installation.
cd /home/ubuntu/offline-bundle
./install.sh

# Core CNI/runtime state.
sudo k3s crictl info
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get runtimeclass nvidia
ip address show cni0

# Workloads and GPU.
sudo k3s kubectl get pods -A
sudo k3s kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}{"\n"}'
sudo nvidia-smi

# vLLM from inside the cluster.
sudo k3s kubectl -n llm exec deployment/vllm -- \
  curl -fsS http://127.0.0.1:8000/v1/models

# NVMe identity (must remain unchanged across reruns).
sudo blkid -s UUID -o value /dev/nvme1n1
```

## Repository state and work left

The repair is implemented in the working tree but is not committed. Local
Ansible syntax and diff checks pass; commit the changes if desired.
Generated/downloaded internet artifacts remain only in
gitignored `offline-bundle/payload/`; important versioned sources remain under
`offline-bundle/` outside `payload/`.

The EC2 stack is still running and billable. When testing is complete:

```bash
aws cloudformation delete-stack --region eu-west-2 --stack-name k3s-on-prem
aws cloudformation wait stack-delete-complete \
  --region eu-west-2 --stack-name k3s-on-prem
```
