## 1. Repository Layout

- [x] 1.1 Create an app-of-apps source folder for the Argo CD root Application and child Application manifests.
- [x] 1.2 Create a separate repository-like `agent` app folder with source code, container metadata, manifests or Helm chart, values, and README.
- [x] 1.3 Add the `agent` child Application manifest that points to the future local Git mirror URL for the `agent` repository.
- [x] 1.4 Add root app-of-apps manifests that point to the future local Git mirror URL for child applications.

## 2. Agent Application

- [x] 2.1 Implement a minimal Python chatbot service using LangChain and an OpenAI-compatible client configuration.
- [x] 2.2 Add optional Langfuse tracing configuration that no-ops when host or credentials are missing.
- [x] 2.3 Add health/readiness endpoints and a chat endpoint suitable for Kubernetes deployment.
- [x] 2.4 Add a Dockerfile and dependency lock/input files for building the agent image on a networked preparation host.
- [x] 2.5 Add Kubernetes or Helm manifests with configurable VLLM endpoint, model, API key, Langfuse settings, image repository/tag, and default `replicaCount: 0`.

## 3. Payload Preparation

- [x] 3.1 Add an Argo CD artifact download script that pins the Argo CD version and stores upstream install manifests under `offline-bundle/payload/`.
- [x] 3.2 Add image discovery or pinned image metadata for Argo CD, registry, nginx Git mirror, and agent images.
- [x] 3.3 Add preparation logic that saves required images as archives under `offline-bundle/payload/`.
- [x] 3.4 Add preparation logic that builds or exports the agent image with all Python dependencies on a networked host.
- [x] 3.5 Extend checksum generation so Argo CD, registry, Git mirror, and agent artifacts are covered by `payload/checksums.txt`.

## 4. Target-Side Offline Bootstrap

- [ ] 4.1 Extend artifact verification to require Argo CD manifests, image archives, GitOps repository content, and image metadata.
- [ ] 4.2 Add Ansible variables for local registry, Argo CD namespace, Git mirror namespace, image archive paths, and app-of-apps settings.
- [ ] 4.3 Add an Ansible role or tasks to import the registry image into K3s/containerd and run a `localhost:5000` registry.
- [ ] 4.4 Add an Ansible role or tasks to tag and push prepared images into `localhost:5000`.
- [ ] 4.5 Add an Ansible role or tasks to create bare Git mirrors from the app-of-apps and agent folders.
- [ ] 4.6 Add an Ansible role or tasks to run the read-only nginx Git mirror from the local registry.

## 5. Argo CD Installation

- [ ] 5.1 Add manifest rendering or patching so every Argo CD image reference uses `localhost:5000`.
- [ ] 5.2 Add Ansible tasks to apply Argo CD manifests after the local registry and Git mirror are ready.
- [ ] 5.3 Add readiness checks for Argo CD workloads and API availability.
- [ ] 5.4 Add Ansible tasks to apply the root app-of-apps Application.
- [ ] 5.5 Add verification that Argo CD registers the `agent` Application from the local Git mirror.

## 6. Documentation

- [ ] 6.1 Update `offline-bundle/README-offline.md` with Argo CD payload preparation, copy, verify, install, and validation steps.
- [ ] 6.2 Update `offline-bundle/VALIDATION.md` with offline Argo CD and app-of-apps validation commands.
- [ ] 6.3 Document how to configure the agent for VLLM and Langfuse once those services exist.
- [ ] 6.4 Document the single-node assumptions for `localhost:5000` registry and read-only Git mirror.

## 7. Validation

- [ ] 7.1 Run shell syntax checks for all new and modified scripts.
- [ ] 7.2 Run local artifact verification against a prepared payload.
- [ ] 7.3 Run Ansible syntax checks for the updated playbook and roles.
- [ ] 7.4 Validate on an isolated Ubuntu 26.04 AMD64 target that K3s, local registry, Git mirror, Argo CD, app-of-apps, and the `agent` Application install without internet access.
- [ ] 7.5 Capture final verification output for nodes, pods, Argo CD Applications, local registry contents, and Git mirror accessibility.
