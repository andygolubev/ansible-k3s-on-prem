## Why

The offline K3s bundle currently installs vLLM with only basic Prometheus scrape hooks; it does not ship a complete offline observability stack, dashboards, log aggregation, distributed tracing, or an operator terminal tool such as `k9s`. This change makes the isolated GPU cluster operationally inspectable without requiring internet access after transfer.

## What Changes

- Add `k9s` to the offline bundle as a locally verified binary, installed on the target host during bootstrap.
- Add an offline observability payload and Ansible role for Prometheus, Grafana, Loki, and Tempo.
- Add vLLM-focused monitoring assets: ServiceMonitor/scrape coverage, Grafana dashboard(s), key alerts or documented alert rules, and validation checks.
- Add log aggregation through Loki for K3s workloads, including vLLM and the demo agent app.
- Add Tempo tracing support and configure the demo agent app to emit OpenTelemetry traces to Tempo when tracing is enabled.
- Replace or supplement the current Langfuse-only tracing path in the demo app so Tempo works inside the isolated cluster without external services.
- Document preparation, installation, validation, and access workflows for k9s, Grafana, Prometheus, Loki, Tempo, and vLLM observability.

## Capabilities

### New Capabilities

- `offline-operator-tooling`: Covers packaging, verifying, installing, and documenting offline operator CLI tools, starting with `k9s`.
- `llm-observability-stack`: Covers offline deployment of Prometheus, Grafana, Loki, Tempo, vLLM dashboards, scrape configuration, logs, traces, and validation.
- `agent-tempo-tracing`: Covers demo agent application instrumentation and configuration for sending traces to in-cluster Tempo.

### Modified Capabilities

- None.

## Impact

- Affected scripts: offline artifact download and verification scripts under `offline-bundle/scripts/`.
- Affected Ansible: `offline-bundle/ansible/playbooks/site.yml`, shared vars, and new or updated roles for operator tooling and observability.
- Affected Kubernetes/GitOps: local image archives, manifests or Helm-rendered YAML for Prometheus, Grafana, Loki, Tempo, dashboards, data sources, and scrape resources.
- Affected app: `apps/agent` Python dependencies, tracing code, Helm values, deployment environment variables, and documentation.
- Affected docs: `README.md`, `offline-bundle/README-offline.md`, `offline-bundle/VALIDATION.md`, and `ARCHITECTURE.md`.
