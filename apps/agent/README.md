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

When Langfuse settings are absent, tracing is disabled and the service still starts.

The Helm chart defaults to `replicaCount: 0` because VLLM is planned for a later task. Set `replicaCount` to a positive number after the model endpoint exists.

