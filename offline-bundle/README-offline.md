# Offline Single-Node K3s Bundle

This bundle installs a single-node K3s server on an isolated Ubuntu 26.04 AMD64 UTM VM.

Ansible runs inside the VM and targets `localhost` with `ansible_connection=local`. SSH and Docker are not required on the VM for the standard workflow.

## Supported Environment

- Preparation host: Linux AMD64, or Docker running `ubuntu:26.04` with `--platform linux/amd64`
- Target VM: Ubuntu 26.04 LTS AMD64
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
  checksums.txt
```

## Prepare Payload With Docker

From the repository root on an internet-connected machine:

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD/offline-bundle:/offline-bundle" \
  -w /offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update &&
    apt-get install -y curl ca-certificates &&
    ./scripts/download-k3s-artifacts.sh &&
    ./scripts/download-ansible-debs.sh &&
    ./scripts/verify-artifacts.sh &&
    du -sh payload
  '
```

That writes all generated files back to `offline-bundle/payload/` on the host.

You can also pin a K3s version:

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD/offline-bundle:/offline-bundle" \
  -w /offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update &&
    apt-get install -y curl ca-certificates &&
    ./scripts/download-k3s-artifacts.sh --k3s-version "v1.33.3+k3s1" &&
    ./scripts/download-ansible-debs.sh &&
    ./scripts/verify-artifacts.sh
  '
```

## Prepare Payload On Linux

On a networked Ubuntu 26.04 AMD64 host:

```bash
cd offline-bundle
./scripts/download-k3s-artifacts.sh
./scripts/download-ansible-debs.sh
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

Both download scripts regenerate:

```text
payload/checksums.txt
```

If K3s version resolution fails, rerun with verbose output:

```bash
VERBOSE=1 ./scripts/download-k3s-artifacts.sh
```

## Copy Bundle To The VM

Copy the complete `offline-bundle/` directory after `payload/` has been prepared.

Preferred transfer options:

1. UTM shared directory.
2. An ISO image containing `offline-bundle/`.
3. Temporary SCP, if you separately choose to install and enable SSH in the VM.

Example once the bundle is visible in the VM:

```bash
cp -a /path/to/offline-bundle "$HOME/offline-bundle"
cd "$HOME/offline-bundle"
```

## Optional Isolation Check

Before installation, confirm the VM cannot reach the internet:

```bash
curl https://github.com
```

This should fail in the isolated target environment.

## Verify Local Payload Offline

Inside the VM:

```bash
cd "$HOME/offline-bundle"
./scripts/verify-artifacts.sh
```

This checks required files, executable bits for K3s scripts, and `payload/checksums.txt`.

## Bootstrap Ansible Offline

Ansible cannot install itself through Ansible. Run the one shell bootstrap step:

```bash
cd "$HOME/offline-bundle"
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
cd "$HOME/offline-bundle/ansible"
ansible-playbook -i inventory.ini playbooks/site.yml
```

The playbook copies local payload artifacts into place and runs the installer with `INSTALL_K3S_SKIP_DOWNLOAD=true`.

The `k3s_offline` role also creates `/var/lib/rancher/k3s/agent/images/.cache.json` by default. This enables K3s conditional image imports for supported releases, avoiding re-importing unchanged air-gap image archives on every K3s restart. Set `k3s_enable_conditional_image_import: false` in `ansible/group_vars/all.yml` to disable it.

## Final Verification

After the playbook completes:

```bash
sudo k3s kubectl get nodes -o wide
sudo systemctl status k3s
```

Expected result: one ready K3s server node.
