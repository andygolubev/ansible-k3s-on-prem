## ADDED Requirements

### Requirement: Agent OpenTelemetry instrumentation

The demo agent application SHALL emit OpenTelemetry traces for HTTP requests and chat model calls when tracing is enabled.

#### Scenario: chat request creates trace spans

- **WHEN** a client sends a request to the agent `/chat` endpoint with tracing enabled
- **THEN** the agent emits a trace containing spans for the inbound HTTP request and the model invocation

#### Scenario: health checks avoid noisy traces

- **WHEN** clients call `/healthz` or `/readyz`
- **THEN** the tracing configuration avoids creating high-cardinality or noisy health check traces where supported by the instrumentation

### Requirement: Tempo endpoint configuration

The agent Helm chart SHALL expose configuration for enabling tracing and selecting the OpenTelemetry export endpoint used for Tempo.

#### Scenario: Tempo tracing values are rendered

- **WHEN** the agent Helm chart is rendered with Tempo tracing enabled
- **THEN** the Deployment includes environment variables for tracing enablement, service name, OTLP endpoint, protocol, and insecure local transport when required

#### Scenario: tracing disabled keeps app running

- **WHEN** tracing is disabled or the endpoint is empty
- **THEN** the agent starts and serves chat requests without trying to export traces

### Requirement: Offline tracing dependencies

The agent container image SHALL include required OpenTelemetry dependencies during connected-host image build so the target does not install Python packages at runtime.

#### Scenario: agent image includes tracing packages

- **WHEN** the connected-host agent image build runs
- **THEN** OpenTelemetry SDK, exporter, and FastAPI or ASGI instrumentation dependencies are installed in the image

#### Scenario: target does not install Python dependencies

- **WHEN** the agent pod starts on the isolated target
- **THEN** it does not run `pip install` or contact external Python package indexes

### Requirement: Tempo replaces external tracing dependency for the demo path

The demo agent SHALL support Tempo tracing without requiring Langfuse or any external tracing service.

#### Scenario: Tempo works without Langfuse settings

- **WHEN** Tempo tracing is enabled and Langfuse settings are absent
- **THEN** chat requests produce traces in Tempo
- **AND** the agent does not fail due to missing Langfuse credentials

#### Scenario: optional Langfuse support remains isolated

- **WHEN** Langfuse settings are provided separately
- **THEN** Langfuse behavior remains independently configurable and does not disable Tempo tracing

### Requirement: Trace content hygiene

The agent tracing implementation SHALL avoid recording full user prompts or model responses in span attributes by default.

#### Scenario: trace attributes exclude prompt bodies

- **WHEN** a chat request is traced
- **THEN** spans include operational metadata such as route, model name, backend URL host, status, and latency
- **AND** spans do not include the full user prompt or full model response unless an explicit debug setting is enabled
