# Architecture

This repository builds and installs an offline, single-node K3s environment for an
isolated Ubuntu 26.04 AMD64 host. The current target is an EC2 `g5.2xlarge`
style node with one NVIDIA A10G GPU, 200 GiB root EBS, and optional NVMe instance
store.

The system is designed around a prepared payload directory. Internet access is
used only on the preparation machine. The target host installs and runs from
local files only.

## High-Level View

```text
                           INTERNET-CONNECTED PREP HOST
              +------------------------------------------------+
              | macOS/Linux + Docker                           |
              |                                                |
              |  offline-bundle/scripts/download-*.sh          |
              |        |                                       |
              |        v                                       |
              |  offline-bundle/payload/                       |
              |    k3s/ debs/ gitops/ gpu/ vllm/ models/ bin/  |
              +------------------------+-----------------------+
                                       |
                                       | copy project root
                                       | shared folder / ISO / SCP
                                       v
                            ISOLATED TARGET HOST
              +------------------------------------------------+
              | Ubuntu 26.04 AMD64                             |
              | localhost Ansible                              |
              |                                                |
              |  install-ansible-offline.sh                    |
              |        |                                       |
              |        v                                       |
              |  ansible/playbooks/site.yml                    |
              |        |                                       |
              |        v                                       |
              |  single-node K3s + GPU + Argo CD + vLLM        |
              +------------------------------------------------+
```

## Repository Layout

```text
ansible-k3s-on-prem/
|-- apps/
|   `-- agent/                    FastAPI/LangChain chatbot and Helm chart
|-- gitops/
|   `-- app-of-apps/              Argo CD root Application and child apps
|-- offline-bundle/
|   |-- ansible/                  Local Ansible inventory, vars, playbook, roles
|   |-- payload/                  Generated offline artifacts, ignored by git
|   |-- scripts/                  Artifact download, verify, and bootstrap scripts
|   `-- VALIDATION.md             Manual validation and acceptance checks
|-- openspec/                     Change proposals, designs, and task records
|-- cloudformation-ec2-ssh-only.yaml
`-- README.md
```

## Target Runtime

```text
                         SINGLE UBUNTU 26.04 TARGET
+----------------------------------------------------------------------------+
| Host OS                                                                    |
|                                                                            |
|  /usr/local/bin/k3s                    /opt/models/Qwen2.5-7B-Instruct     |
|  systemd:k3s                           /var/lib/offline-gitops/git         |
|  systemd:offline-git-mirror            localhost:5000 registry endpoint    |
|                                                                            |
|  +---------------------------- K3s -------------------------------------+  |
|  |                                                                      |  |
|  |  kube-system                                                         |  |
|  |    - K3s core workloads                                              |  |
|  |    - NVIDIA device plugin                                            |  |
|  |                                                                      |  |
|  |  local-registry                                                      |  |
|  |    - registry:2, hostNetwork, hostPort 5000                          |  |
|  |                                                                      |  |
|  |  gitops                                                              |  |
|  |    - Service + Endpoints pointing at host git daemon on port 9418    |  |
|  |                                                                      |  |
|  |  argocd                                                              |  |
|  |    - Argo CD workloads from local-image install manifest             |  |
|  |    - app-of-apps root Application                                    |  |
|  |    - agent child Application                                         |  |
|  |                                                                      |  |
|  |  llm                                                                 |  |
|  |    - vllm Deployment, Service on port 8000                           |  |
|  |    - imagePullPolicy: Never                                          |  |
|  |    - requests/limits: nvidia.com/gpu: 1                              |  |
|  |                                                                      |  |
|  |  agent                                                               |  |
|  |    - FastAPI chatbot, installed by Argo CD from local Git mirror      |  |
|  |    - calls http://vllm.llm.svc.cluster.local:8000/v1                 |  |
|  +----------------------------------------------------------------------+  |
+----------------------------------------------------------------------------+
```

## Offline Payload

The generated payload lives at `offline-bundle/payload/` and is intentionally not
tracked by git.

```text
payload/
|-- bin/
|   `-- crane                         Registry push helper
|-- debs/ubuntu-26.04-amd64/
|   `-- ansible-and-deps/             Local Ansible .deb packages
|-- gitops/
|   |-- argocd/                       Argo CD install manifests
|   `-- images/                       images.tsv and image archives
|-- gpu/
|   |-- debs/nvidia-driver/           NVIDIA driver .deb packages
|   |-- debs/nvidia-ctk/              NVIDIA container toolkit .deb packages
|   |-- images/nvidia-device-plugin.tar
|   `-- device-plugin.yaml
|-- k3s/
|   |-- k3s
|   |-- install.sh
|   |-- k3s-airgap-images-amd64.tar.zst
|   `-- VERSION
|-- models/
|   `-- Qwen2.5-7B-Instruct/
|-- vllm/
|   |-- images/vllm-openai.tar
|   `-- VLLM_IMAGE
`-- checksums.txt
```

## Bootstrap Flow

```text
1. Prepare artifacts on a connected host
   |
   |-- download-k3s-artifacts.sh
   |-- download-ansible-debs.sh
   |-- download-argocd-artifacts.sh
   |-- download-gpu-artifacts.sh
   |-- download-vllm-artifacts.sh
   |-- download-model-artifacts.sh
   `-- verify-artifacts.sh

2. Copy the full project root to the isolated target
   |
   `-- includes offline-bundle/, gitops/app-of-apps/, and apps/agent/

3. Bootstrap Ansible from local .deb files
   |
   `-- sudo offline-bundle/scripts/install-ansible-offline.sh

4. Run local Ansible against localhost
   |
   `-- ansible-playbook -i inventory.ini playbooks/site.yml
         |
         |-- k3s_offline
         |-- gpu_offline
         |-- argocd_offline
         `-- vllm_offline
```

## Ansible Role Responsibilities

```text
site.yml
|
|-- k3s_offline
|   |-- verifies local K3s binary, install script, and air-gap image archive
|   |-- installs /usr/local/bin/k3s
|   |-- copies air-gap images into /var/lib/rancher/k3s/agent/images
|   |-- optionally creates .cache.json for conditional image imports
|   `-- runs install.sh with INSTALL_K3S_SKIP_DOWNLOAD=true
|
|-- gpu_offline
|   |-- verifies NVIDIA driver, container toolkit, and device plugin payloads
|   |-- formats and mounts /dev/nvme1n1 at /mnt/nvme when present
|   |-- installs NVIDIA .deb packages with apt --no-download fallback
|   |-- configures the NVIDIA runtime for K3s containerd
|   |-- imports the NVIDIA device plugin image archive
|   |-- applies the device plugin DaemonSet
|   `-- validates nvidia-smi and nvidia.com/gpu allocatable capacity
|
|-- argocd_offline
|   |-- imports prepared GitOps image archives into K3s containerd
|   |-- deploys a host-network local registry at localhost:5000
|   |-- pushes prepared images into the local registry with bundled crane
|   |-- creates bare Git mirrors from gitops/app-of-apps and apps/agent
|   |-- starts host-side git daemon on port 9418
|   |-- exposes that daemon in-cluster as git://git-mirror.gitops.svc.cluster.local
|   |-- installs Argo CD from a local-image manifest
|   `-- applies the app-of-apps root Application
|
`-- vllm_offline
    |-- imports the vLLM image archive into K3s containerd
    |-- copies the model snapshot into /opt/models
    |-- applies llm namespace, vLLM Deployment, and Service
    |-- optionally applies ServiceMonitor when the CRD exists
    `-- validates /v1/models from inside the vLLM Deployment
```

## GitOps Runtime Flow

```text
                      +------------------------------+
                      | host git daemon              |
                      | /var/lib/offline-gitops/git  |
                      | app-of-apps.git              |
                      | agent.git                    |
                      +---------------+--------------+
                                      |
                                      | port 9418
                                      v
                     +-------------------------------+
                     | gitops/git-mirror Service     |
                     | Endpoints -> target host IP   |
                     +---------------+---------------+
                                     |
             git://git-mirror.gitops.svc.cluster.local
                                     |
          +--------------------------+--------------------------+
          |                                                     |
          v                                                     v
+--------------------+                              +--------------------+
| app-of-apps        | reads applications/          | agent              |
| Argo CD App        +----------------------------->| Argo CD App        |
| namespace: argocd  |                              | namespace: argocd  |
+--------------------+                              +---------+----------+
                                                               |
                                                               | Helm chart
                                                               v
                                                     +--------------------+
                                                     | agent namespace    |
                                                     | FastAPI chatbot    |
                                                     +--------------------+
```

## Model Serving Flow

```text
+---------------------+        OpenAI-compatible HTTP        +-------------+
| agent FastAPI app    +------------------------------------->| vLLM Service|
| namespace: agent     | http://vllm.llm.svc.cluster.local    | namespace:  |
| /chat endpoint       | /v1                                 | llm         |
+---------------------+                                      +------+------+
                                                                    |
                                                                    v
                                                          +-----------------+
                                                          | vLLM pod        |
                                                          | Qwen2.5-7B      |
                                                          | /models mount   |
                                                          | 1 NVIDIA GPU    |
                                                          +--------+--------+
                                                                   |
                                                                   v
                                                          +-----------------+
                                                          | hostPath        |
                                                          | /opt/models     |
                                                          +-----------------+
```

The vLLM Deployment sets `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, and
`HF_DATASETS_OFFLINE=1`. The image uses `imagePullPolicy: Never`, so the vLLM
image must already be imported into K3s containerd.

## Storage And Network Assumptions

```text
Root EBS, persistent:
  /opt/models/Qwen2.5-7B-Instruct
  /var/lib/rancher/k3s
  /var/lib/offline-gitops/git

NVMe instance store, ephemeral when present:
  /mnt/nvme
  /mnt/nvme/model-cache

In-cluster services:
  local-registry.local-registry.svc.cluster.local, plus host localhost:5000
  git-mirror.gitops.svc.cluster.local:9418
  vllm.llm.svc.cluster.local:8000
  agent.agent.svc.cluster.local:8080
```

The current GPU role formats `/dev/nvme1n1` whenever that device exists. Treat
that device as disposable instance-store storage for this setup.

## Validation Entry Points

Use `offline-bundle/VALIDATION.md` for the full validation checklist. The core
checks are:

```text
offline-bundle/scripts/verify-artifacts.sh
sudo offline-bundle/scripts/install-ansible-offline.sh
ansible-playbook -i offline-bundle/ansible/inventory.ini offline-bundle/ansible/playbooks/site.yml
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n llm get pods -o wide
curl -fsS http://127.0.0.1:5000/v2/
git ls-remote git://127.0.0.1/app-of-apps.git HEAD
```
