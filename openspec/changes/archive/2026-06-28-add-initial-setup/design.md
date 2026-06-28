## Context

The repository currently contains planning material for an offline single-node K3s installer, but no executable bundle structure. The target environment is an isolated Ubuntu 24.04 AMD64 UTM VM where Ansible runs inside the VM and targets `localhost`. Because the VM has no installation-time internet access, all K3s artifacts and Ubuntu `.deb` packages needed to install Ansible must be downloaded ahead of time on a networked Linux AMD64 preparation host.

The initial setup must keep artifact download concerns separate from offline installation. Download scripts prepare the repository bundle while online; the VM uses only files already present under `offline-bundle/`.

## Goals / Non-Goals

**Goals:**

- Create an `offline-bundle/` tree matching the planned layout.
- Provide Linux AMD64-only scripts that download the latest K3s binary, install script, air-gap image archive, and Ubuntu 24.04 AMD64 Ansible package dependencies.
- Allow downloaded binaries and packages to be committed when repository size remains practical.
- Install Ansible offline from local `.deb` files before running Ansible.
- Use Ansible with `ansible_connection=local`, so SSH is not required for the standard localhost installation path.
- Install K3s from local artifacts with `INSTALL_K3S_SKIP_DOWNLOAD=true`.
- Provide checksum generation, checksum verification, and operator documentation.

**Non-Goals:**

- Supporting multi-node K3s clusters.
- Supporting non-Ubuntu guests, non-AMD64 guests, or non-Linux preparation hosts.
- Supporting remote SSH-driven Ansible execution as the primary workflow.
- Vendoring artifacts when package or binary size makes repository storage impractical.
- Pinning a K3s version in the initial setup; the preparation script downloads the latest available stable release when run.

## Decisions

- Keep the installable bundle under `offline-bundle/`.
  - Rationale: The repo can contain planning, scripts, and future project metadata without mixing them with files copied to the VM.
  - Alternative considered: Make the repository root itself the bundle. That makes VM copy instructions simpler but pollutes the install payload with development metadata.

- Split online preparation scripts from offline installation scripts.
  - Rationale: Online scripts can use network and package repository tools, while offline scripts must be auditable and fail instead of reaching the internet.
  - Alternative considered: One script that both downloads and installs. That creates a higher risk of accidental network access inside the isolated VM.

- Use Linux AMD64 as the only supported artifact preparation host.
  - Rationale: It matches the target architecture and avoids Docker-on-macOS or cross-platform package download edge cases in the first implementation.
  - Alternative considered: macOS support through Docker. The user explicitly chose Linux AMD64-only preparation.

- Use local Ansible execution and omit SSH packages from required dependencies.
  - Rationale: `ansible_connection=local` applies playbooks to localhost without SSH. This reduces offline package volume and setup complexity.
  - Alternative considered: Always include `openssh-server`. It is unnecessary for the standard workflow and should not be required.

- Download the latest K3s release during bundle preparation.
  - Rationale: The initial workflow should fetch current K3s artifacts without maintaining a version constant in the repository.
  - Alternative considered: Pin an exact version. Pinning improves reproducibility but was not requested for the initial setup.

- Generate Ansible role scaffolds with `ansible-galaxy role init`.
  - Rationale: The plan requires role templates to originate from the Ansible CLI, and doing so preserves conventional role structure.
  - Alternative considered: Hand-writing minimal role directories. That would violate the planned role creation requirement.

## Risks / Trade-offs

- Repository size may grow significantly if `.deb` packages and K3s air-gap images are committed. -> Mitigation: Document size checks and keep scripts able to regenerate artifacts if binaries are excluded.
- Latest K3s downloads are less reproducible than pinned versions. -> Mitigation: Record checksums after download and verify them before installation.
- The offline `.deb` set can be incomplete if downloaded outside a clean Ubuntu 24.04 AMD64 package environment. -> Mitigation: Document the required preparation host and verify offline installation with `apt-get --no-download`.
- K3s installation can fail if artifacts are missing, corrupt, or in unexpected paths. -> Mitigation: Provide `verify-artifacts.sh` and Ansible tasks that copy from known bundle paths.
- `ansible-galaxy role init` may not be available before Ansible is installed on a development/preparation host. -> Mitigation: Make role scaffold generation an implementation-time prerequisite on an environment with Ansible available, distinct from offline VM bootstrap.
