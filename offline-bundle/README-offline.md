# Offline Single-Node K3s Bundle

This bundle installs a single-node K3s server on an isolated Ubuntu 24.04 AMD64 UTM VM.

Ansible runs inside the VM and targets `localhost` with `ansible_connection=local`. SSH is not required for the standard workflow.

## Supported Environment

- Preparation host: Linux AMD64, Ubuntu 24.04 for `.deb` downloads
- Target VM: Ubuntu 24.04 LTS AMD64
- Cluster: single-node K3s server
- Network during install: isolated, no internet access

## 1. Prepare Artifacts Online

Run these commands on a networked Linux AMD64 host before copying the bundle into the VM:

```bash
cd offline-bundle
./scripts/download-k3s-artifacts.sh
./scripts/download-ansible-debs.sh
./scripts/verify-artifacts.sh
```

`download-k3s-artifacts.sh` follows the K3s GitHub releases page and downloads the latest release at execution time. The K3s binary and air-gap image tarball always use the same resolved version:

- `artifacts/k3s/k3s`
- `artifacts/k3s/install.sh`
- `artifacts/k3s/k3s-airgap-images-amd64.tar.zst`
- `artifacts/k3s/VERSION`

The download URL follows the official K3s air-gap form, for example:

```bash
curl -L -o k3s-airgap-images-amd64.tar.zst \
  "https://github.com/k3s-io/k3s/releases/download/v1.33.3%2Bk3s1/k3s-airgap-images-amd64.tar.zst"
```

`download-ansible-debs.sh` downloads Ubuntu 24.04 AMD64 packages for local Ansible execution. The default package set intentionally does not include `openssh-server`.

Both download scripts regenerate `checksums.txt`.

If K3s version resolution fails, rerun with verbose output:

```bash
VERBOSE=1 ./scripts/download-k3s-artifacts.sh
```

You can also bypass channel lookup with an explicit version:

```bash
./scripts/download-k3s-artifacts.sh --k3s-version 'v1.33.3+k3s1'
```

## 2. Decide Whether To Commit Artifacts

Downloaded K3s artifacts and `.deb` packages are trackable by default. Before committing binaries, check their size:

```bash
du -sh artifacts
find artifacts -type f -not -name .gitkeep -printf '%s %p\n' | sort -nr | head
```

Commit the downloaded artifacts when the repository size is acceptable for your workflow. If the artifacts are too large, leave them out of the repository and regenerate them with the download scripts on a suitable online preparation host.

The offline install contract is the same either way: the target VM must receive a complete `offline-bundle/` containing the artifacts and matching `checksums.txt`.

## 3. Copy Bundle To The VM

Preferred transfer options:

1. UTM shared directory.
2. An ISO image containing `offline-bundle/`.
3. Temporary SCP, if you separately choose to install and enable SSH in the VM.

Example once the bundle is visible in the VM:

```bash
cp -a /path/to/offline-bundle "$HOME/offline-bundle"
cd "$HOME/offline-bundle"
```

## 4. Optional Isolation Check

Before installation, confirm the VM cannot reach the internet:

```bash
curl https://github.com
```

This should fail in the isolated target environment.

## 5. Verify Local Artifacts Offline

Inside the VM:

```bash
cd "$HOME/offline-bundle"
./scripts/verify-artifacts.sh
```

This checks required files, executable bits for K3s scripts, and `checksums.txt`.

## 6. Bootstrap Ansible Offline

Ansible cannot install itself through Ansible. Run the one shell bootstrap step:

```bash
cd "$HOME/offline-bundle"
sudo ./scripts/install-ansible-offline.sh
```

The bootstrap script installs only local `.deb` packages and uses:

```bash
apt-get install -f -y --no-download
```

If dependencies are missing from the bundle, the command fails instead of downloading from the internet.

## 7. Install K3s With Local Ansible

Run the bundled playbook:

```bash
cd "$HOME/offline-bundle/ansible"
ansible-playbook -i inventory.ini playbooks/site.yml
```

The playbook copies local artifacts into place and runs the installer with `INSTALL_K3S_SKIP_DOWNLOAD=true`.

The `k3s_offline` role also creates `/var/lib/rancher/k3s/agent/images/.cache.json` by default. This enables K3s conditional image imports for supported releases, avoiding re-importing unchanged air-gap image archives on every K3s restart. Set `k3s_enable_conditional_image_import: false` in `ansible/group_vars/all.yml` to disable it.

## 8. Final Verification

After the playbook completes:

```bash
sudo k3s kubectl get nodes -o wide
sudo systemctl status k3s
```

Expected result: one ready K3s server node.
