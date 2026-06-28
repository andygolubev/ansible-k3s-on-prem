## Context

The current offline bundle provisions single-node K3s, GPU support, Argo CD, the demo agent app, and vLLM. vLLM already has pod scrape annotations and an optional `ServiceMonitor`, but the repository does not currently package or deploy Prometheus, Grafana, Loki, Tempo, Grafana dashboards, or a trace backend. The agent app currently supports optional Langfuse tracing, which is not the same as an in-cluster Tempo path and is not enough for a fully offline observability story.

The bundle also lacks offline operator tooling beyond standard host and `kubectl` commands. `k9s` should be prepared with the rest of the payload and installed on the isolated target without network access.

## Goals / Non-Goals

**Goals:**

- Package and install `k9s` as a target-side operator tool.
- Package and deploy an offline observability stack containing Prometheus, Grafana, Loki, and Tempo.
- Include the Kubernetes metrics components needed to make vLLM and GPU dashboards useful.
- Provide Grafana datasources and dashboards for vLLM, GPU, pod health, logs, and traces.
- Instrument the demo agent app with OpenTelemetry so chat requests are visible in Tempo.
- Keep installation repeatable in the existing offline payload and local Ansible model.

**Non-Goals:**

- Multi-node production observability HA.
- Long-term durable observability storage beyond the current single-node proof of concept.
- Replacing Argo CD with an external Git server or cloud observability service.
- Requiring Langfuse for tracing.

## Decisions

**1. Use the existing offline payload model for k9s and observability artifacts.** Download scripts will place binaries, image archives, rendered manifests, dashboards, and checksums under `offline-bundle/payload/`. Target-side Ansible will verify and install from local files. Alternative considered: rely on Helm repos at install time. Rejected because the target is intentionally isolated.

**2. Deploy observability with an Ansible role before vLLM.** The role should load images, push them into the local registry when needed, apply CRDs and manifests, and wait for core services. Running it before `vllm_offline` lets the existing vLLM ServiceMonitor be applied during the vLLM role instead of being skipped until a later rerun. Alternative considered: make observability a GitOps app only. Rejected for the first implementation because Argo CD itself benefits from being observable and CRD ordering is easier in Ansible.

**3. Include Prometheus Operator-compatible resources where practical.** The current vLLM role already checks for the ServiceMonitor CRD, so using Prometheus Operator semantics fits existing code. The prepared manifests can come from pinned chart renders or checked-in YAML, but the target must not fetch charts or images.

**4. Include Grafana provisioning.** Grafana should start with Prometheus, Loki, and Tempo datasources already configured, plus at least one vLLM/GPU dashboard. Alternative considered: document manual dashboard import. Rejected because the cluster is offline and the demo should be usable immediately.

**5. Use OpenTelemetry for agent traces to Tempo.** The agent should emit OTLP traces to an in-cluster collector or directly to Tempo using configurable environment variables. Langfuse support can remain optional, but Tempo tracing must not depend on Langfuse credentials or external network access.

**6. Keep default retention and storage modest.** The target is a single GPU node with finite root EBS. Prometheus, Loki, and Tempo should use bounded retention and simple single-node storage defaults, with documentation explaining how to tune them.

## Risks / Trade-offs

- Observability images increase payload size -> Pin exact versions, document expected size, and extend checksum verification so missing artifacts fail early.
- Prometheus, Loki, Tempo, and Grafana consume CPU, memory, and disk on the same node as vLLM -> Use conservative defaults, bounded retention, and validation checks for node pressure.
- CRDs and operator manifests are ordering-sensitive -> Apply CRDs first, wait for establishment, then apply dependent resources.
- Metrics names vary across vLLM and NVIDIA exporter versions -> Pin versions and include dashboard panels that match the pinned payload; document metric validation commands.
- Direct OTLP-to-Tempo may differ from collector-based routing -> Prefer an OpenTelemetry Collector gateway if included in the stack; otherwise make the endpoint configurable so the app can target Tempo directly.
- Existing Langfuse code could conflict with OpenTelemetry callbacks -> Keep both optional and independently gated by environment variables, with Tempo enabled by default in the offline chart values.

## Migration Plan

1. Add the k9s and observability artifact download steps to the connected-host preparation flow.
2. Extend artifact verification to cover k9s, observability images, manifests, dashboards, and checksums.
3. Add Ansible roles for operator tooling and observability, then wire them into `site.yml` before `vllm_offline`.
4. Update vLLM ServiceMonitor and dashboards to match the installed Prometheus stack.
5. Update the agent app dependencies, tracing implementation, and Helm values for Tempo/OpenTelemetry.
6. Update docs and validation commands for k9s, Grafana, Prometheus targets, Loki log queries, Tempo traces, and vLLM dashboards.
7. Rollback by removing the observability role from `site.yml`, deleting the observability namespaces, and leaving the existing vLLM serving path intact.

## Open Questions

- Should observability be installed purely by Ansible, or should Ansible bootstrap it and then hand steady-state management to Argo CD in a later change?
- Which exact component versions should be pinned for Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector, kube-state-metrics, node-exporter, and NVIDIA DCGM exporter?
- Should the first implementation use persistent volumes on root EBS, or bounded `emptyDir` storage for the proof of concept?
