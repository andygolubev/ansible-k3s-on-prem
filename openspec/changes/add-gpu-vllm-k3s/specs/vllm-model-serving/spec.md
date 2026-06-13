## ADDED Requirements

### Requirement: vLLM GPU deployment for Qwen model

The deployment SHALL run the vLLM OpenAI-compatible API server serving `Qwen/Qwen2.5-7B-Instruct` on the GPU as a single replica in a dedicated namespace (e.g. `llm`), exposed by a Service on port 8000 internally. The pod SHALL request and limit `nvidia.com/gpu: 1` and SHALL set conservative CPU and memory requests appropriate for `g5.2xlarge` shared with other services. An Ingress SHALL be added only if the project already uses ingress; otherwise the Service is internal only.

#### Scenario: vLLM scheduled on the GPU

- **WHEN** the vLLM manifests are applied to the cluster
- **THEN** a single vLLM pod is scheduled on the GPU node with `nvidia.com/gpu: 1` requested and limited
- **AND** a Service exposes port 8000 within the cluster

#### Scenario: Conservative single-node sizing

- **WHEN** the vLLM Deployment is defined
- **THEN** it uses 1 replica, low default concurrency, and CPU/memory requests that leave headroom for the other services on the node

### Requirement: Offline local model loading

vLLM SHALL load the model exclusively from a preloaded local model directory mounted into the pod (e.g. `--model /models/Qwen2.5-7B-Instruct`), with Hugging Face cache/offline environment configured so no download is attempted at runtime. The pod SHALL NOT require internet access to start or serve requests.

#### Scenario: Model loads from local path

- **WHEN** the vLLM pod starts
- **THEN** it loads weights, tokenizer, and config from the mounted local model directory
- **AND** no request is made to Hugging Face or any external registry

#### Scenario: Offline enforcement

- **WHEN** the pod is started with outbound internet blocked
- **THEN** vLLM still reaches a ready state and serves the model

### Requirement: vLLM serving configuration

The vLLM container SHALL be configured with GPU execution and the following conservative arguments: `--dtype float16`, `--max-model-len 4096`, and `--gpu-memory-utilization 0.85`. The container image SHALL be a pinned tag or digest matching the offline bundle and SHALL NOT use `latest`. Readiness and liveness probes SHALL be defined against the API server.

#### Scenario: Conservative GPU args applied

- **WHEN** the vLLM Deployment manifest is inspected
- **THEN** the container args include `--dtype float16`, `--max-model-len 4096`, and `--gpu-memory-utilization 0.85`
- **AND** the image reference is a pinned tag or digest, not `latest`

#### Scenario: Probes report readiness

- **WHEN** vLLM has finished loading the model
- **THEN** the readiness probe passes and the Service begins routing traffic
- **AND** the liveness probe restarts the pod if the API server becomes unresponsive

### Requirement: OpenAI-compatible API availability

Once ready, the vLLM server SHALL expose the OpenAI-compatible API such that `/v1/models` returns the served Qwen model and `/v1/chat/completions` answers a basic chat request. The documentation SHALL include an example `curl` command for `/v1/chat/completions`.

#### Scenario: Model listing

- **WHEN** a client calls `GET /v1/models` against the vLLM Service
- **THEN** the response lists the served `Qwen/Qwen2.5-7B-Instruct` model

#### Scenario: Chat completion

- **WHEN** a client POSTs a basic request to `/v1/chat/completions`
- **THEN** the server returns a valid chat completion response

### Requirement: vLLM and model artifacts in offline bundle

The offline bundle SHALL include the vLLM container image, any required CUDA/runtime base images, the complete `Qwen/Qwen2.5-7B-Instruct` snapshot (weights, tokenizer, config, and Hugging Face snapshot metadata needed for offline loading), and all vLLM Kubernetes manifests, each with SHA256 checksums. A documented script/step SHALL place the model files into the correct local model directory on the target.

#### Scenario: Model snapshot verified

- **WHEN** the verification script runs
- **THEN** it confirms the model weights, tokenizer, config, and snapshot metadata are present with matching checksums

#### Scenario: Images loaded into containerd

- **WHEN** the image load step runs on the offline target
- **THEN** the vLLM and CUDA images are imported into K3s/containerd from local archives without pulling from any registry

### Requirement: vLLM observability

The deployment SHOULD expose vLLM Prometheus metrics via a scrape config or ServiceMonitor when a Prometheus stack is present, and the documentation SHALL list the key metrics to watch: GPU utilization, GPU memory, request latency, token throughput, pod restarts, and OOM kills.

#### Scenario: Metrics scraped

- **WHEN** a Prometheus stack is deployed and the vLLM scrape config/ServiceMonitor is applied
- **THEN** Prometheus collects vLLM request and throughput metrics from the pod

#### Scenario: Metrics to watch documented

- **WHEN** an operator reads the observability documentation
- **THEN** it lists GPU utilization, GPU memory, request latency, token throughput, pod restarts, and OOM kills as the metrics to monitor
