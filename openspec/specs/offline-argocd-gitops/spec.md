# offline-argocd-gitops Specification

## Purpose
TBD - created by archiving change add-argocd-agent-gitops. Update Purpose after archive.
## Requirements
### Requirement: Offline Argo CD Payload Preparation
The system SHALL prepare all Argo CD, local registry, local Git mirror, and GitOps bootstrap artifacts on a networked preparation host before transfer to the isolated target.

#### Scenario: Argo CD artifacts are downloaded
- **WHEN** the operator runs the Argo CD artifact preparation script
- **THEN** the script stores a pinned Argo CD version, install manifests, required image metadata, and image archives under `offline-bundle/payload/`

#### Scenario: Registry and Git mirror images are included
- **WHEN** the Argo CD payload is prepared
- **THEN** the payload includes image archives and helper binaries required to populate the local registry without target-side downloads

#### Scenario: Payload checksums include GitOps artifacts
- **WHEN** artifact preparation completes
- **THEN** `offline-bundle/payload/checksums.txt` includes the Argo CD manifests, image archives, version files, and generated GitOps payload files

### Requirement: Offline Argo CD Artifact Verification
The system SHALL verify Argo CD and GitOps payload artifacts before installation on the isolated target.

#### Scenario: Required Argo CD files are present
- **WHEN** the operator runs the artifact verification script on the target
- **THEN** the script validates required Argo CD manifests, image archives, and version metadata

#### Scenario: Missing image archive fails verification
- **WHEN** any required Argo CD, registry, Git mirror, or app image archive is absent
- **THEN** artifact verification fails before installation changes are applied

### Requirement: Offline Target Storage
The system SHALL provision enough root storage for the offline bundle, imported K3s image content, and locally mirrored GitOps images.

#### Scenario: EC2 root volume supports offline installation
- **WHEN** a new SSH-only EC2 target stack is deployed with defaults
- **THEN** the root EBS volume is at least 30 GiB gp3

### Requirement: Local Registry Bootstrap
The system SHALL create a local registry on the single-node K3s target and load prepared images into it before installing Argo CD or GitOps-managed apps.

#### Scenario: Registry starts from offline image
- **WHEN** the offline registry bootstrap runs
- **THEN** it imports the registry image from the payload into K3s/containerd and starts a registry reachable from the node as `localhost:5000`

#### Scenario: Prepared images are pushed locally
- **WHEN** the local registry is reachable
- **THEN** the bootstrap pushes every required Argo CD and app image archive into `localhost:5000`

#### Scenario: Registry bootstrap is idempotent
- **WHEN** the registry bootstrap is rerun
- **THEN** existing local registry resources and already-pushed images do not cause the run to fail

### Requirement: Argo CD Offline Installation
The system SHALL install Argo CD into K3s without pulling manifests or images from the internet.

#### Scenario: Argo CD manifests reference local images
- **WHEN** Argo CD manifests are applied on the target
- **THEN** every container image reference used by Argo CD points to `localhost:5000`

#### Scenario: Argo CD becomes ready offline
- **WHEN** the Argo CD installation playbook completes
- **THEN** Argo CD workloads in the Argo CD namespace are available without target-side internet access

### Requirement: Local GitOps Source
The system SHALL expose the copied app-of-apps and application repository folders as Git repositories reachable by Argo CD inside the isolated cluster.

#### Scenario: Bare Git mirrors are generated
- **WHEN** the GitOps bootstrap runs on the target
- **THEN** it creates bare Git repositories from the app-of-apps folder and the agent app folder

#### Scenario: Argo CD can read repository URLs
- **WHEN** Argo CD reconciles the root Application
- **THEN** the configured `git://` repository URLs resolve to the local Git mirror service from inside the cluster

### Requirement: App-Of-Apps Bootstrap
The system SHALL provide an app-of-apps root Application that bootstraps child Argo CD Applications from local GitOps sources.

#### Scenario: Root Application is applied
- **WHEN** the Argo CD bootstrap playbook applies the root app-of-apps manifest
- **THEN** Argo CD creates or reconciles the child `agent` Application from the local app-of-apps repository

#### Scenario: App-of-apps source is repository-backed
- **WHEN** the root Application is inspected
- **THEN** its source references the local Git mirror rather than a public internet repository

### Requirement: Offline GitOps Documentation
The system SHALL document the offline Argo CD preparation, transfer, install, and verification workflow.

#### Scenario: Operator follows documentation
- **WHEN** an operator follows the offline README for Argo CD
- **THEN** the documented flow prepares payload artifacts, copies the bundle, verifies artifacts, bootstraps the registry, installs Argo CD, applies app-of-apps, and verifies Argo CD Applications

