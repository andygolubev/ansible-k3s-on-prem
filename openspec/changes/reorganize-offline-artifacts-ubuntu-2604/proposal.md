## Why

The offline bundle currently mixes source files with downloaded payload files, making it harder to delete and regenerate binaries/packages without risking bundle source files. The bundle also needs to move its documented target and package preparation workflow from Ubuntu 24.04 to Ubuntu 26.04 AMD64, with clear Docker instructions for preparing offline artifacts from a mounted bundle.

## What Changes

- Add a single generated/downloaded payload directory under `offline-bundle/` that contains all files produced by download scripts.
- Update `.gitignore` so only that generated payload directory is ignored, while bundle scripts, Ansible files, docs, and OpenSpec files remain trackable.
- Update K3s artifact paths, `.deb` package paths, checksum generation, checksum verification, offline bootstrap, and Ansible variables to use the generated payload directory.
- Update all Ubuntu references from Ubuntu 24.04 to Ubuntu 26.04 for the target VM and package preparation workflow.
- Update the Ansible package download script to require Ubuntu 26.04 AMD64 package metadata and output directory naming.
- Add README instructions for running an AMD64 Ubuntu 26.04 Docker container with the repository or `offline-bundle/` mounted to download K3s binaries and Ubuntu packages for offline use.
- Preserve the offline install workflow: copy the prepared `offline-bundle/` to the VM, verify artifacts, install Ansible from local `.deb` packages, and run the localhost Ansible playbook.

## Capabilities

### New Capabilities

- `offline-artifact-cache`: Defines the generated artifact directory layout, git-ignore behavior, Ubuntu 26.04 package preparation, and Docker-based online preparation workflow for offline bundle payloads.

### Modified Capabilities

- None.

## Impact

- Affected files include `.gitignore`, `offline-bundle/scripts/*`, `offline-bundle/ansible/group_vars/all.yml`, `offline-bundle/ansible/roles/k3s_offline/tasks/main.yml`, `offline-bundle/README-offline.md`, `offline-bundle/VALIDATION.md`, and existing artifact placeholder paths.
- Existing downloaded files under the old `offline-bundle/artifacts/` layout will need to be deleted or moved into the new generated payload directory.
- Users will regenerate payloads by deleting the ignored generated directory and rerunning the download scripts, preferably inside an AMD64 Ubuntu 26.04 Docker container.
