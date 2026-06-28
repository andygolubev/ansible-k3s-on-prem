# offline-operator-tooling Specification

## Purpose
TBD - created by archiving change add-k9s-observability-stack. Update Purpose after archive.
## Requirements
### Requirement: k9s offline artifact

The offline bundle SHALL include a pinned `k9s` Linux AMD64 artifact and checksum metadata under the generated payload directory.

#### Scenario: k9s artifact is prepared

- **WHEN** the connected-host artifact preparation flow runs
- **THEN** it downloads or builds a pinned `k9s` Linux AMD64 artifact into `offline-bundle/payload/`
- **AND** records the artifact in `payload/checksums.txt`

#### Scenario: k9s artifact is verified

- **WHEN** `offline-bundle/scripts/verify-artifacts.sh` runs after k9s preparation
- **THEN** it verifies that the `k9s` artifact exists and matches the recorded checksum

### Requirement: k9s target installation

The target bootstrap SHALL install `k9s` from the offline payload without requiring internet access.

#### Scenario: k9s is installed offline

- **WHEN** the local Ansible playbook runs on the isolated target
- **THEN** `k9s` is installed into a directory on the target `PATH`
- **AND** the installed binary is executable by operators with shell access

#### Scenario: missing k9s payload fails early

- **WHEN** the k9s installation role runs and the k9s artifact is missing
- **THEN** the role fails with an actionable message before making unrelated changes

### Requirement: k9s operator documentation

The repository SHALL document how to prepare, install, and run `k9s` in the isolated K3s environment.

#### Scenario: operator opens documentation

- **WHEN** an operator reads the offline bundle documentation
- **THEN** it includes the k9s preparation step, install location, and a basic command for opening the local K3s cluster

#### Scenario: k9s validation command works

- **WHEN** an operator runs the documented k9s version or help command on the target
- **THEN** the command succeeds without network access

