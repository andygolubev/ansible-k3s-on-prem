## ADDED Requirements

### Requirement: Offline observability payload

The offline bundle SHALL include all artifacts required to install Prometheus, Grafana, Loki, Tempo, and supporting Kubernetes metrics components without target-side internet access.

#### Scenario: observability artifacts are prepared

- **WHEN** the connected-host observability download flow runs
- **THEN** it stores pinned image archives, manifests or rendered chart output, Grafana dashboards, datasource definitions, and version metadata under `offline-bundle/payload/`
- **AND** it records those artifacts in `payload/checksums.txt`

#### Scenario: observability artifacts are verified

- **WHEN** `offline-bundle/scripts/verify-artifacts.sh` runs after observability preparation
- **THEN** it verifies required observability images, manifests, dashboards, datasource files, and version metadata

### Requirement: Offline observability deployment

The local Ansible playbook SHALL deploy Prometheus, Grafana, Loki, Tempo, and required supporting metrics components from local payload artifacts.

#### Scenario: observability stack installs offline

- **WHEN** the playbook runs on the isolated target
- **THEN** the observability stack is installed without pulling images, charts, or manifests from external networks
- **AND** all installed observability workloads reach a ready state

#### Scenario: observability role fails on missing artifacts

- **WHEN** an observability image, manifest, dashboard, or datasource artifact is missing
- **THEN** the observability role fails with an actionable message before applying partial resources

### Requirement: Prometheus metrics coverage

The observability stack SHALL collect Kubernetes, node, GPU, and vLLM metrics needed to operate the single-node GPU cluster.

#### Scenario: Prometheus discovers vLLM metrics

- **WHEN** vLLM is deployed and Prometheus is running
- **THEN** Prometheus scrapes the vLLM `/metrics` endpoint through a ServiceMonitor or equivalent scrape configuration

#### Scenario: Prometheus collects GPU and cluster health metrics

- **WHEN** the observability stack is running
- **THEN** Prometheus collects GPU utilization, GPU memory, pod restart, node CPU, node memory, and node disk metrics from local cluster sources

### Requirement: Grafana dashboards and datasources

Grafana SHALL be provisioned with Prometheus, Loki, and Tempo datasources and at least one dashboard focused on vLLM and GPU operations.

#### Scenario: Grafana datasources are provisioned

- **WHEN** Grafana starts in the isolated cluster
- **THEN** Prometheus, Loki, and Tempo datasources are available without manual UI configuration

#### Scenario: vLLM dashboard is available

- **WHEN** an operator opens Grafana
- **THEN** a vLLM dashboard displays request rate, error rate, request latency, token throughput, running or waiting requests, GPU utilization, GPU memory, pod restarts, and OOM indicators where the underlying metrics are available

### Requirement: Loki log aggregation

The observability stack SHALL collect Kubernetes workload logs into Loki and make vLLM and agent logs queryable from Grafana.

#### Scenario: vLLM logs are queryable

- **WHEN** the vLLM pod emits logs
- **THEN** those logs are available through Loki with labels that identify the `llm` namespace and vLLM workload

#### Scenario: agent logs are queryable

- **WHEN** the demo agent pod emits logs
- **THEN** those logs are available through Loki with labels that identify the `agent` namespace and agent workload

### Requirement: Tempo trace backend

The observability stack SHALL provide an in-cluster Tempo trace backend that accepts OpenTelemetry traces from cluster workloads.

#### Scenario: Tempo accepts OTLP traces

- **WHEN** a workload sends OpenTelemetry traces to the documented in-cluster endpoint
- **THEN** Tempo accepts and stores the trace data

#### Scenario: traces are visible in Grafana

- **WHEN** trace data exists in Tempo
- **THEN** Grafana can search or open those traces through the provisioned Tempo datasource

### Requirement: Observability validation

The repository SHALL provide validation commands for Prometheus, Grafana, Loki, Tempo, and the vLLM dashboard path.

#### Scenario: validation checks targets and datasources

- **WHEN** an operator follows the validation guide
- **THEN** it confirms Prometheus targets are up, Grafana datasources exist, Loki returns recent workload logs, Tempo contains a demo trace, and vLLM dashboard metrics populate

#### Scenario: no external pulls occur

- **WHEN** the observability stack is installed on the target
- **THEN** Kubernetes events do not show failed external image pulls for observability workloads
