## ADDED Requirements

### Requirement: Agent Repository Layout
The system SHALL provide a repository-like folder for the `agent` application separate from the app-of-apps folder.

#### Scenario: Agent source folder exists
- **WHEN** the repository is inspected
- **THEN** it contains an `agent` application folder with service source code, container build metadata, and deployment manifests

#### Scenario: App-of-apps references agent repository
- **WHEN** the app-of-apps manifests are inspected
- **THEN** the `agent` Argo CD Application references the local Git mirror for the separate `agent` repository folder

### Requirement: LangChain Chatbot Service
The `agent` application SHALL implement a simple chatbot service using LangChain.

#### Scenario: Chat endpoint receives a prompt
- **WHEN** a client submits a chat prompt to the agent service
- **THEN** the service forwards the prompt through LangChain to the configured OpenAI-compatible model endpoint

#### Scenario: VLLM endpoint is configurable
- **WHEN** the agent deployment is rendered
- **THEN** the VLLM/OpenAI-compatible base URL, model name, and API key are configurable through Kubernetes values or environment variables

### Requirement: Langfuse Instrumentation
The `agent` application SHALL support Langfuse tracing configuration without requiring internet access during deployment.

#### Scenario: Langfuse settings are provided
- **WHEN** Langfuse host and credentials are configured
- **THEN** the agent service enables Langfuse tracing for chatbot requests

#### Scenario: Langfuse settings are absent
- **WHEN** Langfuse host or credentials are not configured
- **THEN** the agent service starts without failing and disables or no-ops Langfuse tracing

### Requirement: Agent Container Image
The system SHALL build and package the `agent` container image on a networked preparation host for offline deployment.

#### Scenario: Agent image archive is generated
- **WHEN** the payload preparation flow runs for applications
- **THEN** it builds or pulls the `agent` image with all Python dependencies and stores an image archive under `offline-bundle/payload/`

#### Scenario: Agent image is loaded into local registry
- **WHEN** the target-side registry bootstrap runs
- **THEN** it pushes the prepared `agent` image into `localhost:5000` and the agent manifests reference that local image

### Requirement: Agent Kubernetes Deployment
The `agent` application SHALL include Kubernetes or Helm manifests deployable by Argo CD in the isolated K3s cluster.

#### Scenario: Argo CD syncs agent app
- **WHEN** the app-of-apps root Application is synced
- **THEN** Argo CD creates the `agent` Application and applies the agent deployment manifests from the local Git mirror

#### Scenario: VLLM is not installed yet
- **WHEN** the agent manifests are deployed before VLLM exists
- **THEN** the deployment uses documented defaults that avoid blocking Argo CD bootstrap and make the missing model backend explicit

### Requirement: Agent Configuration Documentation
The system SHALL document how to configure the agent app for VLLM and Langfuse.

#### Scenario: Operator reads agent documentation
- **WHEN** an operator opens the agent app documentation
- **THEN** it explains the VLLM endpoint settings, Langfuse settings, local image naming, and expected behavior before VLLM is installed
