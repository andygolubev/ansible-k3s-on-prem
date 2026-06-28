## Why

The offline K3s bundle can currently install only the cluster itself; it does not provide a repeatable way to install platform add-ons or deploy applications after the isolated target is created. Adding Argo CD and a sample `agent` app gives the project a GitOps bootstrap path that works without internet access and creates a foundation for later VLLM-backed workloads.

## What Changes

- Add offline Argo CD support to the bundle, including scripts to download/pin the Argo CD install source and required container images on a networked preparation host.
- Extend payload verification and Ansible installation so Argo CD artifacts are copied to the isolated target, loaded into the local K3s/containerd image store, and applied to the cluster without pulling from the internet.
- Add a GitOps app-of-apps repository folder that bootstraps child Argo CD Applications, starting with an `agent` application.
- Add a separate repository-like folder for the `agent` application, containing a simple LangChain chatbot service configured for Langfuse telemetry and a local VLLM-compatible endpoint.
- Document the preparation, transfer, installation, and verification flow for offline Argo CD and the sample app.

## Capabilities

### New Capabilities
- `offline-argocd-gitops`: Covers preparing, verifying, transferring, loading, and installing Argo CD and GitOps manifests in an isolated K3s environment.
- `agent-chatbot-app`: Covers the repository layout and Kubernetes deployment contract for the sample LangChain/Langfuse chatbot that calls a local VLLM-compatible endpoint.

### Modified Capabilities
- None.

## Impact

- Affected code: `offline-bundle/scripts/`, `offline-bundle/ansible/`, `offline-bundle/README-offline.md`, `offline-bundle/VALIDATION.md`.
- New repo content: an app-of-apps folder and an `agent` app repository folder with app source, container build metadata, and Kubernetes/Helm manifests.
- New generated payload content under `offline-bundle/payload/` for Argo CD manifests, images, and agent image archives.
- New operational dependency on local image import into K3s/containerd; no target-side internet access is allowed during installation.
- VLLM itself remains a non-goal for this change; the agent app will reference a configurable local VLLM endpoint that a later change will provide.
