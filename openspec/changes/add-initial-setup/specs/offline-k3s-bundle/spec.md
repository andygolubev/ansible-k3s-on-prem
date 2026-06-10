## ADDED Requirements

### Requirement: Bundle Layout
The repository SHALL provide an `offline-bundle/` directory containing the artifacts, Ansible files, scripts, checksums, and offline usage documentation needed to install single-node K3s on an isolated Ubuntu 24.04 AMD64 VM.

#### Scenario: Bundle tree exists
- **WHEN** the initial setup is implemented
- **THEN** `offline-bundle/` contains `artifacts/k3s/`, `artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps/`, `ansible/`, `scripts/`, `checksums.txt`, and `README-offline.md`

### Requirement: K3s Artifact Download
The bundle SHALL include a Linux AMD64 preparation script that downloads the latest K3s binary, K3s install script, and AMD64 air-gap image archive into `offline-bundle/artifacts/k3s/`.

#### Scenario: K3s artifacts are downloaded
- **WHEN** the operator runs the K3s artifact download script on a networked Linux AMD64 host
- **THEN** `offline-bundle/artifacts/k3s/` contains `k3s`, `install.sh`, and `k3s-airgap-images-amd64.tar.zst`

#### Scenario: Downloaded K3s artifacts are executable or readable
- **WHEN** the K3s artifact download script completes
- **THEN** `k3s` and `install.sh` are executable and `k3s-airgap-images-amd64.tar.zst` is readable

### Requirement: Offline Ansible Package Download
The bundle SHALL include a Linux AMD64 preparation script that downloads Ubuntu 24.04 AMD64 `.deb` packages required to install and run Ansible locally in the VM.

#### Scenario: Ansible packages are downloaded
- **WHEN** the operator runs the Ansible package download script on a networked Linux AMD64 Ubuntu 24.04-compatible host
- **THEN** `offline-bundle/artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps/` contains `.deb` packages for Ansible and its required dependencies

#### Scenario: SSH packages are not required by default
- **WHEN** the Ansible package download script prepares packages for the standard localhost workflow
- **THEN** the package set does not require `openssh-server` solely for Ansible execution

### Requirement: Checksum Verification
The bundle SHALL provide scripts or documented commands to generate and verify checksums for downloaded artifacts before offline installation.

#### Scenario: Checksums are generated
- **WHEN** the operator prepares the bundle online
- **THEN** `offline-bundle/checksums.txt` records checksums for downloaded K3s artifacts and `.deb` packages

#### Scenario: Checksums are verified
- **WHEN** the operator runs artifact verification before offline installation
- **THEN** verification succeeds only if all recorded files exist and match `offline-bundle/checksums.txt`

### Requirement: Offline Ansible Bootstrap
The bundle SHALL include an offline bootstrap script that installs Ansible from local `.deb` packages without requiring internet access.

#### Scenario: Bootstrap uses only local packages
- **WHEN** the operator runs `sudo ./scripts/install-ansible-offline.sh` from inside `offline-bundle/` on the isolated VM
- **THEN** the script installs local packages from `artifacts/debs/ubuntu-24.04-amd64/ansible-and-deps/` and uses package manager recovery with `--no-download`

#### Scenario: Bootstrap fails instead of downloading
- **WHEN** required local package dependencies are missing
- **THEN** the bootstrap script fails rather than downloading packages from the internet

### Requirement: Localhost Ansible Configuration
The bundle SHALL configure Ansible to run inside the VM against `localhost` using a local connection.

#### Scenario: Inventory targets localhost locally
- **WHEN** the operator runs the bundled playbook with the bundled inventory
- **THEN** Ansible targets a `local_k3s` host group containing `localhost ansible_connection=local`

### Requirement: Offline K3s Installation
The bundled Ansible playbook SHALL install a single-node K3s server using only local K3s artifacts.

#### Scenario: K3s installs without network downloads
- **WHEN** the operator runs `ansible-playbook -i inventory.ini playbooks/site.yml` from `offline-bundle/ansible/`
- **THEN** Ansible copies the K3s binary, install script, and air-gap image archive to their required target paths and runs the installer with `INSTALL_K3S_SKIP_DOWNLOAD=true`

#### Scenario: K3s image archive is placed for air-gap import
- **WHEN** the Ansible playbook applies the K3s offline role
- **THEN** the air-gap image archive is present at `/var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst`

### Requirement: Installation Verification
The bundle SHALL verify that the single-node K3s server becomes available after installation.

#### Scenario: Ansible waits for node readiness command
- **WHEN** the K3s installer has created the systemd service
- **THEN** the Ansible role retries `/usr/local/bin/k3s kubectl get nodes` until the command succeeds or the retry limit is reached

#### Scenario: Documentation describes final checks
- **WHEN** the operator completes the playbook run
- **THEN** `README-offline.md` documents final verification with `sudo k3s kubectl get nodes -o wide` and `sudo systemctl status k3s`
