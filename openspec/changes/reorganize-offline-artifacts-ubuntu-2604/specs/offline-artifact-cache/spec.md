## ADDED Requirements

### Requirement: Generated Payload Directory
The offline bundle SHALL store every downloaded/generated offline artifact under `offline-bundle/payload/`.

#### Scenario: Payload root contains downloaded artifacts
- **WHEN** the artifact download scripts complete successfully
- **THEN** K3s artifacts, Ubuntu `.deb` packages, version metadata, and checksums are stored under `offline-bundle/payload/`

#### Scenario: Payload can be deleted and regenerated
- **WHEN** an operator deletes `offline-bundle/payload/` and reruns the download scripts
- **THEN** the scripts recreate the required payload subdirectories and downloaded files

### Requirement: Git Ignore Scope
The repository SHALL ignore only the generated payload directory for offline bundle artifacts.

#### Scenario: Payload is ignored
- **WHEN** `.gitignore` is evaluated
- **THEN** `offline-bundle/payload/` is ignored by git

#### Scenario: Bundle source remains trackable
- **WHEN** `.gitignore` is evaluated
- **THEN** `offline-bundle/scripts/`, `offline-bundle/ansible/`, `offline-bundle/README-offline.md`, and `offline-bundle/VALIDATION.md` remain trackable

### Requirement: Ubuntu 26.04 Baseline
The offline bundle SHALL use Ubuntu 26.04 AMD64 as the target VM and package preparation baseline.

#### Scenario: Documentation uses Ubuntu 26.04
- **WHEN** a user reads offline bundle documentation
- **THEN** target VM and package preparation instructions refer to Ubuntu 26.04 AMD64

#### Scenario: Package path uses Ubuntu 26.04
- **WHEN** the Ansible package download script writes `.deb` files
- **THEN** it stores them under `offline-bundle/payload/debs/ubuntu-26.04-amd64/ansible-and-deps/`

#### Scenario: Package script validates Ubuntu 26.04
- **WHEN** the Ansible package download script runs
- **THEN** it verifies the preparation environment uses Ubuntu 26.04 AMD64-compatible package metadata

### Requirement: Payload-Aware Installation
The offline bootstrap and Ansible install workflow SHALL read payload files from the generated payload directory.

#### Scenario: Offline bootstrap reads payload debs
- **WHEN** the operator runs the offline Ansible bootstrap script
- **THEN** the script installs local `.deb` files from `offline-bundle/payload/debs/ubuntu-26.04-amd64/ansible-and-deps/`

#### Scenario: Ansible reads K3s payload artifacts
- **WHEN** the bundled Ansible playbook installs K3s
- **THEN** it copies the K3s binary, install script, and air-gap image from `offline-bundle/payload/k3s/`

#### Scenario: Artifact verification reads payload checksums
- **WHEN** the operator runs the artifact verification script
- **THEN** it validates required payload files against `offline-bundle/payload/checksums.txt`

### Requirement: Docker Preparation Documentation
The offline README SHALL document how to use Docker to prepare payload files with an AMD64 Ubuntu 26.04 container and a mounted bundle.

#### Scenario: Docker command mounts the bundle
- **WHEN** a user follows the Docker preparation documentation
- **THEN** the command runs `ubuntu:26.04` for `linux/amd64` and mounts the repository or `offline-bundle/` into the container

#### Scenario: Docker command downloads all payload files
- **WHEN** the documented Docker command completes successfully
- **THEN** it has run the K3s artifact download script, the Ansible package download script, and payload verification from the mounted bundle

### Requirement: Ubuntu 24.04 References Removed
The offline bundle SHALL not retain Ubuntu 24.04 references in active scripts, Ansible variables, or README instructions.

#### Scenario: Active files reference Ubuntu 26.04
- **WHEN** active bundle files are searched for Ubuntu version references
- **THEN** they refer to Ubuntu 26.04 instead of Ubuntu 24.04
