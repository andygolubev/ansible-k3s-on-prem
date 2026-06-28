## 1. Bundle Structure

- [x] 1.1 Create the `offline-bundle/` directory tree with `artifacts/k3s/`, `artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps/`, `ansible/`, `scripts/`, `checksums.txt`, and `README-offline.md`.
- [x] 1.2 Add placeholder tracking files where needed so required empty artifact directories are represented before binary downloads.
- [x] 1.3 Review `.gitignore` rules so downloaded K3s and `.deb` artifacts can be committed when size is acceptable, while generated transient files stay ignored.

## 2. Online Artifact Preparation Scripts

- [x] 2.1 Add `offline-bundle/scripts/download-k3s-artifacts.sh` for Linux AMD64 hosts to download the latest K3s binary, install script, and `k3s-airgap-images-amd64.tar.zst` into `artifacts/k3s/`.
- [x] 2.2 Ensure the K3s download script sets executable permissions on `artifacts/k3s/k3s` and `artifacts/k3s/install.sh`.
- [x] 2.3 Add `offline-bundle/scripts/download-ansible-debs.sh` for Linux AMD64 Ubuntu 24.04-compatible hosts to download Ansible and required dependencies into `artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps/`.
- [x] 2.4 Keep `openssh-server` out of the default Ansible package set unless implementation testing proves it is required for localhost Ansible execution.
- [x] 2.5 Add checksum generation for all downloaded K3s artifacts and `.deb` packages into `offline-bundle/checksums.txt`.
- [x] 2.6 Add `offline-bundle/scripts/verify-artifacts.sh` to verify required files and checksum integrity before offline installation.

## 3. Offline Bootstrap

- [x] 3.1 Add `offline-bundle/scripts/install-ansible-offline.sh` to install local `.deb` packages from `artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps/`.
- [x] 3.2 Ensure the bootstrap script uses `dpkg -i` and package manager recovery with `apt-get install -f -y --no-download`.
- [x] 3.3 Ensure the bootstrap script fails when required dependencies are absent instead of trying to download from the internet.

## 4. Ansible Bundle

- [x] 4.1 Add `offline-bundle/ansible/ansible.cfg` configured for the bundled inventory and roles path.
- [x] 4.2 Add `offline-bundle/ansible/inventory.ini` with `[local_k3s]` and `localhost ansible_connection=local`.
- [x] 4.3 Add `offline-bundle/ansible/group_vars/all.yml` for bundle paths and K3s install settings.
- [x] 4.4 Generate `offline-bundle/ansible/roles/bootstrap_ansible` with `ansible-galaxy role init bootstrap_ansible` from the roles directory.
- [x] 4.5 Generate `offline-bundle/ansible/roles/k3s_offline` with `ansible-galaxy role init k3s_offline` from the roles directory.
- [x] 4.6 Add `offline-bundle/ansible/playbooks/site.yml` that targets `local_k3s`, uses privilege escalation, and applies the `k3s_offline` role.

## 5. K3s Offline Role

- [x] 5.1 Implement `k3s_offline` tasks to create `/var/lib/rancher/k3s/agent/images`.
- [x] 5.2 Implement tasks to copy `artifacts/k3s/k3s` to `/usr/local/bin/k3s` with executable permissions.
- [x] 5.3 Implement tasks to copy `artifacts/k3s/k3s-airgap-images-amd64.tar.zst` to `/var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst`.
- [x] 5.4 Implement tasks to copy `artifacts/k3s/install.sh` to `/tmp/k3s-install.sh` with executable permissions.
- [x] 5.5 Implement the K3s server install command with `INSTALL_K3S_SKIP_DOWNLOAD=true` and `server --write-kubeconfig-mode 644`.
- [x] 5.6 Implement readiness verification that retries `/usr/local/bin/k3s kubectl get nodes` until it succeeds or reaches the retry limit.

## 6. Documentation

- [x] 6.1 Write `offline-bundle/README-offline.md` with online preparation steps on Linux AMD64.
- [x] 6.2 Document copying `offline-bundle/` into the UTM Ubuntu 24.04 AMD64 VM.
- [x] 6.3 Document optional VM network isolation verification before installation.
- [x] 6.4 Document offline Ansible bootstrap and local playbook execution commands.
- [x] 6.5 Document final verification with `sudo k3s kubectl get nodes -o wide` and `sudo systemctl status k3s`.
- [x] 6.6 Document artifact size checks and the policy for committing downloaded binaries and packages when repository size is practical.

## 7. Validation

- [x] 7.1 Run shell syntax checks for all bundle scripts.
- [x] 7.2 Run Ansible syntax validation for the bundled playbook when Ansible is available.
- [x] 7.3 Run the artifact verification script against prepared artifacts when downloads are available.
- [x] 7.4 Record any validation that cannot be run locally and the environment needed to complete it.
