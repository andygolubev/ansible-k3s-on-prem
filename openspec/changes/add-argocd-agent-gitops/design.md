## Context

The repository currently prepares an offline K3s payload, copies it to an isolated Ubuntu 26.04 AMD64 target, bootstraps Ansible from local `.deb` files, and installs a single-node K3s server from local artifacts. The target has no internet access by design, so Argo CD, application images, and repository content must be prepared on a networked host and copied as part of the bundle.

Argo CD cannot use public Git repositories or public registries from the isolated cluster. The change therefore needs both an image distribution mechanism and a Git source reachable from inside K3s. The user also wants an app-of-apps repository and a separate repository-like folder for an `agent` app that will later talk to a VLLM service.

## Goals / Non-Goals

**Goals:**
- Prepare all Argo CD, local Git mirror, local registry, and `agent` image artifacts into `offline-bundle/payload/`.
- Install a single-node local registry reachable as `localhost:5000` by K3s/containerd and preload it with all required images.
- Install Argo CD offline using manifests rendered to reference only images in the local registry.
- Add an app-of-apps repository folder that defines an Argo CD root Application and an `agent` child Application.
- Add a separate repository-like `agent` app folder with a small LangChain chatbot service, Dockerfile, and Kubernetes/Helm deployment manifests.
- Seed a local read-only Git mirror from the copied repository folders so Argo CD can reconcile from an in-cluster reachable `repoURL`.

**Non-Goals:**
- Installing or operating VLLM. The `agent` app will only reference a configurable local VLLM-compatible endpoint.
- Installing Langfuse itself. The `agent` app will expose Langfuse configuration and degrade cleanly when Langfuse settings are absent.
- Providing a multi-node production registry or a full Git hosting service.
- Supporting target-side downloads during installation.

## Decisions

1. Use a localhost registry for all post-K3s images.
   - Decision: add an offline registry bootstrap that imports a pinned `registry:2` image into K3s/containerd, runs it with `hostPort: 5000`, configures K3s/containerd for `localhost:5000`, and pushes all prepared images into that registry before applying Argo CD.
   - Rationale: the user explicitly requested loading images into a local registry, and a localhost registry works for a single-node K3s cluster without requiring cluster DNS during image pulls.
   - Alternatives considered: relying only on K3s air-gap image imports is simpler, but it is an image store rather than a registry and does not satisfy the local-registry requirement.

2. Use manifest rendering for Argo CD rather than requiring Helm on the target.
   - Decision: download/pin upstream Argo CD install manifests on the preparation host, rewrite image references to `localhost:5000/...`, copy them in the payload, and apply them with `kubectl`.
   - Rationale: this avoids adding Helm as a required target dependency and keeps Argo CD installation deterministic offline.
   - Alternatives considered: installing Argo CD from a Helm chart is viable, but it adds chart download/rendering concerns and still requires image rewriting.

3. Provide a read-only local Git mirror for Argo CD.
   - Decision: run a host-side read-only `git daemon` over bare repositories generated from `gitops/app-of-apps/` and `apps/agent/`, and expose it inside the cluster through a Service and Endpoints. The root Application points to the app-of-apps mirror, and the agent Application points to the agent mirror.
   - Rationale: Argo CD requires a repository source reachable from its repo-server pod; copied host folders alone are not sufficient inside an isolated cluster.
   - Alternatives considered: applying all manifests directly with Ansible would install workloads, but it would bypass GitOps and not exercise Argo CD reconciliation.

4. Keep repository-like folders as source-of-truth inputs.
   - Decision: create repo folders in the main repository, then generate bare Git mirrors from those folders during offline bootstrap.
   - Rationale: this gives the user visible app-of-apps and agent repo content while still making it consumable by Argo CD inside the isolated target.

5. Build the `agent` app image on the preparation host.
   - Decision: include a script that builds or pulls the `agent` image while internet access is available, exports it as an archive, verifies it via checksums, and loads/pushes it to the local registry on the target.
   - Rationale: Python dependencies for LangChain and Langfuse cannot be installed from the isolated target.

## Risks / Trade-offs

- Local registry availability before Argo CD install -> bootstrap the registry first, wait for it to answer on `localhost:5000/v2/`, and fail early if image push fails.
- Argo CD image list drift across versions -> pin the Argo CD version and derive image references from downloaded manifests during payload preparation.
- Git mirror complexity -> keep the mirror read-only, generated from repo folders, and exposed with `git://`; document that it is an offline bootstrap mechanism rather than a collaborative Git server.
- Agent app starts before VLLM exists -> configure replicas to zero by default and document the values to enable it after the VLLM change lands.
- Langfuse endpoint is absent in isolated environments -> make Langfuse configuration optional and avoid failing startup when credentials are not supplied.
- Single-node assumptions -> document that `localhost:5000` registry and hostPath-backed Git mirror are for the existing single-node K3s target only.

## Migration Plan

1. Generate the expanded payload on a networked preparation host.
2. Copy the complete bundle to the isolated target.
3. Verify checksums and required Argo CD, registry, Git mirror, and agent artifacts.
4. Install K3s if it is not already installed.
5. Bootstrap the local registry and push prepared images into `localhost:5000`.
6. Bootstrap the local Git mirror from copied app-of-apps and agent folders.
7. Apply Argo CD manifests and wait for Argo CD components to become available.
8. Apply the root app-of-apps Application and verify the `agent` Application is registered and healthy according to its configured replica mode.

Rollback is manual and local: delete the root Argo CD Application, delete the Argo CD namespace, delete local registry/Git mirror manifests, and remove generated payload files if a clean rebuild is needed.

## Open Questions

- None.
