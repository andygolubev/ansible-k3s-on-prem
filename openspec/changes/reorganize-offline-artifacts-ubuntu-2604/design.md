## Context

The current offline bundle has trackable source files and generated payload files under the same `offline-bundle/artifacts/` tree. That makes cleanup and git-ignore rules more fragile: deleting downloaded K3s binaries and `.deb` packages can accidentally remove placeholder/source structure, and ignoring individual binary patterns becomes easy to miss as new artifact types are added.

The target and preparation baseline is also changing from Ubuntu 24.04 AMD64 to Ubuntu 26.04 AMD64. The `.deb` package download workflow must therefore resolve packages using Ubuntu 26.04 metadata, and README examples should show a reproducible Docker command that mounts the bundle into an AMD64 Ubuntu 26.04 container.

## Goals / Non-Goals

**Goals:**

- Keep bundle source files, scripts, docs, and Ansible content trackable under `offline-bundle/`.
- Put every downloaded/generated offline payload file under one directory, `offline-bundle/payload/`.
- Ignore only `offline-bundle/payload/` in git.
- Let users delete `offline-bundle/payload/` and rerun download scripts to regenerate binaries, packages, checksums, and version metadata.
- Update all Ubuntu target/preparation paths and documentation from Ubuntu 24.04 to Ubuntu 26.04.
- Document the Docker workflow for downloading payloads with `ubuntu:26.04` on `linux/amd64`.

**Non-Goals:**

- Installing Docker inside the offline VM.
- Supporting Ubuntu 24.04 package preparation after this change.
- Supporting non-AMD64 package preparation.
- Changing the single-node K3s install architecture.
- Archiving prior OpenSpec changes.

## Decisions

- Use `offline-bundle/payload/` as the only generated artifact root.
  - Rationale: A short, explicit name makes it clear this directory can be deleted and regenerated.
  - Alternative considered: Keep `offline-bundle/artifacts/` and ignore it wholesale. That is workable, but the existing name already mixed source placeholders and payload concepts.

- Move K3s artifacts to `offline-bundle/payload/k3s/`.
  - Rationale: K3s binary, install script, air-gap tarball, and version metadata are generated/downloaded payloads.
  - Alternative considered: Keep K3s files under `artifacts/k3s/` and only move `.deb` packages. That would leave generated files split across multiple locations.

- Move Ubuntu packages to `offline-bundle/payload/debs/ubuntu-26.04-amd64/ansible-and-deps/`.
  - Rationale: The OS/version/architecture is encoded in the path and aligns package dependencies with the target VM baseline.
  - Alternative considered: Use a generic `payload/debs/ansible-and-deps/` path. That hides the distro compatibility contract.

- Place `checksums.txt` under `offline-bundle/payload/checksums.txt`.
  - Rationale: Checksums describe generated payload files and should be regenerated with that payload.
  - Alternative considered: Keep checksums at the bundle root. That keeps verification visible but means deleting payloads leaves a stale tracked checksum file.

- Keep Docker as a preparation-host convenience only.
  - Rationale: Docker solves package download reproducibility on the online host, but the offline VM should remain simple and does not need Docker.
  - Alternative considered: Require Docker on the VM. That conflicts with the offline single-node K3s workflow and adds unnecessary runtime dependencies.

## Risks / Trade-offs

- Ubuntu `26.04` Docker images or package metadata may not be available in every environment at implementation time. -> Mitigation: Make the image tag configurable in docs/scripts if needed, but default all references to `ubuntu:26.04` as requested.
- Existing downloaded artifacts under `offline-bundle/artifacts/` may be left behind. -> Mitigation: Add migration tasks to remove or move old generated artifact files and document payload regeneration.
- Ignoring the whole `payload/` directory means downloaded artifacts will not be committed by default. -> Mitigation: This matches the requested workflow; users can still force-add a payload snapshot if explicitly needed.
- Checksums under the ignored payload directory are not tracked. -> Mitigation: Verification requires regenerating checksums with the payload and copying the complete prepared bundle to the VM.
