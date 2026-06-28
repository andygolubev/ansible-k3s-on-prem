## Why

This repository needs an initial implementation path for building and using a self-contained offline installer bundle for a single-node K3s cluster. The target VM is isolated during installation, so all K3s artifacts, Ansible packages, automation, and verification guidance must be present before the bundle is copied into the VM.

## What Changes

- Add an `offline-bundle/` repository subtree containing the installable bundle layout.
- Add Linux AMD64-only scripts to download the latest K3s release artifacts and Ubuntu 24.04 AMD64 Ansible package dependencies before offline use.
- Add an offline Ansible bootstrap script that installs only local `.deb` packages and does not require SSH for localhost execution.
- Add an Ansible localhost inventory, configuration, and playbook for installing single-node K3s from local artifacts.
- Add generated Ansible role scaffolds for `bootstrap_ansible` and `k3s_offline`, with `k3s_offline` performing the offline K3s installation and readiness verification.
- Add artifact checksum generation and verification so committed or copied binaries can be validated.
- Add offline usage documentation covering bundle preparation, transfer to the UTM VM, bootstrap, playbook execution, and final verification.
- Commit downloaded binaries and packages when repository/package size allows; otherwise document size-driven alternatives without changing the offline install contract.

## Capabilities

### New Capabilities

- `offline-k3s-bundle`: Defines the required behavior for preparing and using a self-contained offline bundle that installs single-node K3s on Ubuntu 24.04 AMD64 through localhost Ansible.

### Modified Capabilities

- None.

## Impact

- New files under `offline-bundle/`, including scripts, Ansible configuration, inventory, playbooks, roles, artifact directories, checksums, and README documentation.
- Download scripts depend on a networked Linux AMD64 preparation host with Ubuntu package tooling available.
- Offline VM installation depends only on pre-downloaded local artifacts, Ubuntu 24.04 AMD64 baseline tools, and one shell bootstrap command before Ansible runs locally.
