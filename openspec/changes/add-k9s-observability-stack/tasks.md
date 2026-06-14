## 1. Version And Artifact Planning

- [ ] 1.1 Choose and document pinned versions for k9s, Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector, kube-state-metrics, node-exporter, and NVIDIA DCGM exporter.
- [ ] 1.2 Define the generated payload layout for operator tooling and observability artifacts under `offline-bundle/payload/`.
- [ ] 1.3 Identify all required container images, CRDs, manifests, dashboards, and datasource files for the offline observability stack.
- [ ] 1.4 Confirm the current vLLM monitoring gap in docs: existing scrape annotations and ServiceMonitor are present, but Prometheus, Grafana dashboards, Loki, Tempo, and agent Tempo traces are not yet installed.

## 2. k9s Offline Tooling

- [ ] 2.1 Add a connected-host download step for the pinned Linux AMD64 k9s artifact.
- [ ] 2.2 Store k9s under the offline payload and add it to `payload/checksums.txt`.
- [ ] 2.3 Extend `verify-artifacts.sh` to validate the k9s artifact when present or when the operator-tooling payload is expected.
- [ ] 2.4 Add an Ansible role or task group that installs k9s from the payload into a target-side `PATH` directory.
- [ ] 2.5 Add validation that `k9s version` or an equivalent noninteractive command succeeds on the isolated target.

## 3. Observability Payload Preparation

- [ ] 3.1 Add a connected-host script to collect or render pinned observability manifests and CRDs for Prometheus, Grafana, Loki, Tempo, and supporting exporters.
- [ ] 3.2 Save all required observability container images as local archives and include local-registry image references in generated metadata.
- [ ] 3.3 Add Grafana datasource provisioning for Prometheus, Loki, and Tempo.
- [ ] 3.4 Add a vLLM/GPU Grafana dashboard JSON file covering request rate, errors, latency, token throughput, queue or active request gauges, GPU utilization, GPU memory, restarts, and OOM indicators.
- [ ] 3.5 Extend checksum generation and `verify-artifacts.sh` to cover observability images, manifests, dashboards, datasources, and version metadata.

## 4. Observability Installation

- [ ] 4.1 Add an `observability_offline` Ansible role that verifies required payload artifacts before applying resources.
- [ ] 4.2 Load observability image archives into K3s containerd and push images into the local registry when manifests reference `localhost:5000`.
- [ ] 4.3 Apply CRDs before dependent resources and wait for CRD establishment.
- [ ] 4.4 Deploy Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector if selected, kube-state-metrics, node-exporter, and NVIDIA DCGM exporter from local manifests.
- [ ] 4.5 Provision Grafana datasources and dashboards during install.
- [ ] 4.6 Wire `observability_offline` into `offline-bundle/ansible/playbooks/site.yml` before `vllm_offline`.
- [ ] 4.7 Add readiness checks for Prometheus, Grafana, Loki, Tempo, and required exporters.

## 5. vLLM Metrics, Logs, And Dashboards

- [ ] 5.1 Ensure the vLLM ServiceMonitor or equivalent scrape config is applied when the observability stack is present.
- [ ] 5.2 Verify Prometheus target discovery for vLLM, Kubernetes, node, and GPU metrics.
- [ ] 5.3 Configure Loki log collection so `llm` namespace vLLM logs and `agent` namespace logs are queryable with workload labels.
- [ ] 5.4 Validate that Grafana dashboard panels populate from the pinned metric names.
- [ ] 5.5 Add documented queries or alerts for latency, token throughput, GPU memory pressure, pod restarts, and OOM kills.

## 6. Agent Tempo Tracing

- [ ] 6.1 Add OpenTelemetry SDK, OTLP exporter, and FastAPI or ASGI instrumentation dependencies to the agent image build.
- [ ] 6.2 Instrument the agent app so `/chat` requests and model invocations emit spans when Tempo tracing is enabled.
- [ ] 6.3 Add trace attribute hygiene so full prompts and full model responses are not recorded by default.
- [ ] 6.4 Add Helm values and deployment environment variables for tracing enablement, service name, OTLP endpoint, protocol, and local insecure transport.
- [ ] 6.5 Configure default offline chart values to send traces to the in-cluster Tempo or OpenTelemetry Collector endpoint.
- [ ] 6.6 Keep Langfuse optional and independently gated so missing Langfuse settings do not affect Tempo tracing.
- [ ] 6.7 Add a validation path that sends a demo `/chat` request and confirms the trace is visible through Tempo/Grafana.

## 7. Documentation And Validation

- [ ] 7.1 Update `offline-bundle/README-offline.md` with preparation, installation, access, and troubleshooting steps for k9s and the observability stack.
- [ ] 7.2 Update `offline-bundle/VALIDATION.md` with checks for k9s, Prometheus targets, Grafana datasources, Loki log queries, Tempo traces, and vLLM dashboards.
- [ ] 7.3 Update `ARCHITECTURE.md` to include the observability stack, telemetry flow, and k9s operator tooling.
- [ ] 7.4 Add syntax or dry-run validation for new scripts and Ansible roles.
- [ ] 7.5 Run Ansible syntax checks for the updated playbook and roles.
- [ ] 7.6 Document rollback steps for removing observability resources without breaking K3s, Argo CD, vLLM, or the agent app.
