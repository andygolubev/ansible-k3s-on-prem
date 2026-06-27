# Agent Chatbot

`agent` is a small LangChain chatbot service intended to run in the offline K3s cluster after Argo CD bootstraps the app-of-apps repository.

The service calls an OpenAI-compatible local model endpoint. The expected future target is VLLM, but VLLM is not installed by this app.

## Runtime Configuration

- `VLLM_BASE_URL`: OpenAI-compatible base URL. Default: `http://vllm.vllm.svc.cluster.local:8000/v1`
- `VLLM_MODEL`: model name sent to the chat completion endpoint. Default: `local-model`
- `VLLM_API_KEY`: API key sent to the endpoint. Default: `EMPTY`
- `LANGFUSE_HOST`: optional Langfuse host URL.
- `LANGFUSE_PUBLIC_KEY`: optional Langfuse public key.
- `LANGFUSE_SECRET_KEY`: optional Langfuse secret key.
- `TEMPO_TRACING_ENABLED`: enables OpenTelemetry trace export to Tempo when set to `true`.
- `OTEL_SERVICE_NAME`: OpenTelemetry service name. Default: `agent-chatbot`.
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP gRPC endpoint. Default in the chart: `otel-collector.observability.svc.cluster.local:4317`.
- `OTEL_EXPORTER_OTLP_INSECURE`: use insecure local OTLP transport. Default in the chart: `true`.

When Langfuse settings are absent, Langfuse tracing is disabled and the service still starts. Tempo tracing is independent and uses OpenTelemetry; it does not require Langfuse credentials or external network access.

The Helm chart points Tempo tracing at the in-cluster OpenTelemetry Collector by default. Set `tracing.tempo.enabled=false` to disable trace export.
