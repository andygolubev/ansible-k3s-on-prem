# Offline Single-Node K3s Bundle

This bundle installs a single-node K3s server on an isolated Ubuntu 26.04 AMD64 host, such as a UTM VM or EC2 instance.

Ansible runs inside the target host and targets `localhost` with `ansible_connection=local`. Docker is not required on the target, and SSH is only needed if you use SCP or remote shell access to transfer and run the bundle.

## Supported Environment

- Preparation host: Linux AMD64, or Docker running `ubuntu:26.04` with `--platform linux/amd64`
- Target host: Ubuntu 26.04 LTS AMD64
- Cluster: single-node K3s server
- Network during install: isolated, no internet access

## Payload Directory

All downloaded/generated offline files live under:

```text
offline-bundle/payload/
```

This directory is ignored by git. You can delete it and regenerate it with the download scripts.

Generated payload layout:

```text
payload/
  k3s/
    k3s
    install.sh
    k3s-airgap-images-amd64.tar.zst
    VERSION
  debs/
    ubuntu-26.04-amd64/
      ansible-and-deps/
        *.deb
  gitops/
    argocd/
      VERSION
      install.yaml
      install-local.yaml
    images/
      images.tsv
      *.tar
  checksums.txt
```

## Prepare Payload With Docker

From the repository root on an internet-connected machine:

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
    ./scripts/verify-artifacts.sh &&
    du -sh payload
  '
```

That writes all generated files back to `offline-bundle/payload/` on the host.

You can also pin a K3s version:

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace/offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update &&
    apt-get install -y curl ca-certificates &&
    ./scripts/download-k3s-artifacts.sh --k3s-version "v1.33.3+k3s1" &&
    ./scripts/download-ansible-debs.sh &&
    ./scripts/download-argocd-artifacts.sh --argocd-version "v2.14.0" &&
    ./scripts/verify-artifacts.sh
  '
```

## Prepare Payload On Linux

On a networked Ubuntu 26.04 AMD64 host:

```bash
cd offline-bundle
./scripts/download-k3s-artifacts.sh
./scripts/download-ansible-debs.sh
./scripts/download-argocd-artifacts.sh
./scripts/verify-artifacts.sh
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

`download-argocd-artifacts.sh` downloads a pinned Argo CD install manifest, rewrites image references for `localhost:5000`, builds the `agent` image, and saves all required Argo CD, registry, Git mirror, and agent image archives into:

```text
payload/gitops/
```

The default local registry is `localhost:5000`. Override image defaults with `REGISTRY_IMAGE`, `GIT_MIRROR_IMAGE`, `AGENT_IMAGE`, or `LOCAL_REGISTRY`.

All download scripts regenerate:

```text
payload/checksums.txt
```

If K3s version resolution fails, rerun with verbose output:

```bash
VERBOSE=1 ./scripts/download-k3s-artifacts.sh
```

## Copy Bundle To The Target

Copy the project root after `payload/` has been prepared. The Argo CD workflow needs `offline-bundle/`, `gitops/app-of-apps/`, and `apps/agent/` on the target because the playbook generates local Git mirrors from those source folders.

Preferred transfer options:

1. UTM shared directory.
2. An ISO image containing the project root.
3. SCP, if SSH access is available on the target.

Example once the bundle is visible on the target:

```bash
cp -a /path/to/ansible-k3s-on-prem "$HOME/ansible-k3s-on-prem"
cd "$HOME/ansible-k3s-on-prem/offline-bundle"
```

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
./scripts/verify-artifacts.sh
```

This checks required files, executable bits for K3s scripts, and `payload/checksums.txt`.

## Bootstrap Ansible Offline

Ansible cannot install itself through Ansible. Run the one shell bootstrap step:

```bash
cd "$HOME/ansible-k3s-on-prem/offline-bundle"
sudo ./scripts/install-ansible-offline.sh
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

The `argocd_offline` role then imports prepared image archives, starts a single-node local registry at `localhost:5000`, pushes prepared images into it, creates read-only local Git mirrors from `gitops/app-of-apps/` and `apps/agent/`, applies the local-image Argo CD manifests, and applies the root app-of-apps Application.

## Agent App Configuration

The `apps/agent/chart/values.yaml` file controls the sample LangChain chatbot deployment:

- `replicaCount`: defaults to `0` until a local VLLM endpoint is installed.
- `vllm.baseUrl`: OpenAI-compatible local endpoint, expected to be VLLM in a later task.
- `vllm.model`: model name sent to the endpoint.
- `vllm.apiKey`: API key value for the OpenAI-compatible client.
- `langfuse.host`, `langfuse.publicKey`, `langfuse.secretKey`: optional Langfuse tracing settings.

When Langfuse settings are empty, tracing is disabled and the app still starts.

## Single-Node Assumptions

The offline GitOps bootstrap is designed for the current single-node K3s target:

- The registry is exposed as `localhost:5000` on the node and is suitable for local containerd pulls.
- The Git mirror is read-only and generated from copied source folders during bootstrap.
- Multi-node registry distribution, persistent Git hosting, and VLLM installation are outside this workflow.

## Final Verification

After the playbook completes:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl -n argocd get applications
curl -fsS http://127.0.0.1:5000/v2/
sudo systemctl status k3s
```

Expected result: one Ready K3s server node, running core `kube-system` pods, running Argo CD pods, an `agent` Application registered in Argo CD, and a reachable local registry.
