# Offline Single-Node K3s Plan

## Goal

Build a self-contained repository bundle for installing a single-node K3s cluster on an isolated Ubuntu 24.04 AMD64 UTM VM.

Ansible will run inside the VM and target `localhost`. The VM must not need internet access during installation.

## Target Environment

- Host: Intel/AMD64 Mac
- VM platform: UTM
- Guest OS: Ubuntu 24.04 LTS AMD64
- Cluster type: single-node K3s server
- Network: isolated VM, no internet access during install
- Ansible execution: inside the VM
- Ansible target: `localhost`

## Out-Of-Box Ubuntu Notes

Ubuntu 24.04 usually includes:

- `python3`: yes
- `sudo`: yes on standard installs
- `ansible`: no
- `openssh-server`: only if selected during install

Because the VM has no internet access, the repo must include Ubuntu 24.04 AMD64 `.deb` packages for Ansible and its dependencies.

## Bundle Structure

```text
offline-bundle/
  artifacts/
    k3s/
      k3s
      install.sh
      k3s-airgap-images-amd64.tar.zst

    debs/
      ubuntu-24.04-amd64/
        ansible-and-deps/
          *.deb

  ansible/
    ansible.cfg
    inventory.ini
    group_vars/
      all.yml
    playbooks/
      site.yml
    roles/
      bootstrap_ansible/
      k3s_offline/

  scripts/
    download-k3s-artifacts.sh
    download-ansible-debs.sh
    install-ansible-offline.sh
    verify-artifacts.sh

  checksums.txt
  README-offline.md
```

## Required K3s Artifacts

For Ubuntu 24.04 AMD64:

```text
offline-bundle/artifacts/k3s/k3s
offline-bundle/artifacts/k3s/install.sh
offline-bundle/artifacts/k3s/k3s-airgap-images-amd64.tar.zst
```

K3s air-gap images must be copied on the VM to:

```text
/var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst
```

The K3s install must use:

```bash
INSTALL_K3S_SKIP_DOWNLOAD=true
```

## Offline Ansible Packages

The bundle must include local `.deb` packages for:

```text
ansible
ansible-core
python3 dependencies required by ansible
sudo, optional but useful for robustness
openssh-server, optional only if copying/running over SSH is needed
ca-certificates, optional
```

These packages should be downloaded on an internet-connected Ubuntu 24.04 AMD64 environment, for example with Docker:

```bash
docker run --rm -it \
  -v "$PWD/offline-bundle/artifacts/debs/ubuntu-24.04-amd64:/out" \
  ubuntu:24.04 bash
```

Inside the container:

```bash
apt-get update
apt-get install -y --download-only ansible sudo python3

mkdir -p /out/ansible-and-deps
cp /var/cache/apt/archives/*.deb /out/ansible-and-deps/
```

If SSH access to the VM is required:

```bash
apt-get install -y --download-only openssh-server
cp /var/cache/apt/archives/*.deb /out/ansible-and-deps/
```

## Bootstrap Limitation

Ansible cannot install itself before Ansible exists.

Therefore the VM needs one shell bootstrap step:

```bash
cd ~/offline-bundle
sudo ./scripts/install-ansible-offline.sh
```

After that, all K3s installation work should be done through Ansible.

## Offline Ansible Installer Script

`offline-bundle/scripts/install-ansible-offline.sh` should install only local packages:

```bash
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEB_DIR="$DIR/artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps"

sudo dpkg -i "$DEB_DIR"/*.deb || sudo apt-get install -f -y --no-download
```

If dependencies are missing, `apt-get --no-download` must fail instead of trying to reach the internet.

## Ansible Role Creation Requirement

Role templates must be created with the Ansible CLI, not hand-written from scratch.

Run from:

```bash
offline-bundle/ansible/roles/
```

Commands:

```bash
ansible-galaxy role init bootstrap_ansible
ansible-galaxy role init k3s_offline
```

Then edit the generated role files as needed, mainly:

```text
bootstrap_ansible/tasks/main.yml
k3s_offline/tasks/main.yml
```

## Local Inventory

`offline-bundle/ansible/inventory.ini`:

```ini
[local_k3s]
localhost ansible_connection=local
```

## Main Playbook

`offline-bundle/ansible/playbooks/site.yml`:

```yaml
- name: Install offline single-node K3s
  hosts: local_k3s
  become: true
  roles:
    - k3s_offline
```

## K3s Offline Role Responsibilities

The `k3s_offline` role should:

1. Create the K3s image directory:

   ```text
   /var/lib/rancher/k3s/agent/images
   ```

2. Install the K3s binary:

   ```text
   /usr/local/bin/k3s
   ```

3. Copy the K3s air-gap image archive:

   ```text
   /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst
   ```

4. Copy the K3s install script:

   ```text
   /tmp/k3s-install.sh
   ```

5. Install the single-node K3s server:

   ```bash
   INSTALL_K3S_SKIP_DOWNLOAD=true /tmp/k3s-install.sh server --write-kubeconfig-mode 644
   ```

6. Verify the node:

   ```bash
   /usr/local/bin/k3s kubectl get nodes
   ```

## Example Role Tasks

```yaml
- name: Create K3s image directory
  ansible.builtin.file:
    path: /var/lib/rancher/k3s/agent/images
    state: directory
    mode: "0755"

- name: Install K3s binary
  ansible.builtin.copy:
    src: ../../../artifacts/k3s/k3s
    dest: /usr/local/bin/k3s
    mode: "0755"

- name: Copy K3s airgap images
  ansible.builtin.copy:
    src: ../../../artifacts/k3s/k3s-airgap-images-amd64.tar.zst
    dest: /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst
    mode: "0644"

- name: Copy K3s install script
  ansible.builtin.copy:
    src: ../../../artifacts/k3s/install.sh
    dest: /tmp/k3s-install.sh
    mode: "0755"

- name: Install K3s single-node server
  ansible.builtin.command:
    cmd: /tmp/k3s-install.sh server --write-kubeconfig-mode 644
  environment:
    INSTALL_K3S_SKIP_DOWNLOAD: "true"
  args:
    creates: /etc/systemd/system/k3s.service

- name: Wait for K3s node
  ansible.builtin.command:
    cmd: /usr/local/bin/k3s kubectl get nodes
  register: k3s_nodes
  changed_when: false
  retries: 20
  delay: 6
  until: k3s_nodes.rc == 0
```

## Copying Bundle To UTM VM

Preferred options:

1. Use UTM shared directory.
2. Use an ISO image containing `offline-bundle`.
3. Use temporary SSH/SCP if `openssh-server` is installed.

With SSH:

```bash
scp -r offline-bundle youruser@VM_IP:/home/youruser/
```

Then inside the VM:

```bash
cd ~/offline-bundle
sudo ./scripts/install-ansible-offline.sh

cd ansible
ansible-playbook -i inventory.ini playbooks/site.yml
```

## Isolation Verification

Before running the Ansible playbook, verify the VM cannot reach the internet:

```bash
curl https://github.com
```

This should fail.

## Final Verification

After the playbook completes:

```bash
sudo k3s kubectl get nodes -o wide
sudo systemctl status k3s
```

Expected result: one ready K3s server node.
