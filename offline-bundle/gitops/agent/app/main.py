import os
from contextlib import nullcontext
from typing import Any
from urllib.parse import urlparse

from fastapi import FastAPI
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

try:
    from langfuse.callback import CallbackHandler
except Exception:  # pragma: no cover - optional dependency integration
    CallbackHandler = None  # type: ignore[assignment]

try:
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
except Exception:  # pragma: no cover - optional dependency integration
    trace = None  # type: ignore[assignment]
    OTLPSpanExporter = None  # type: ignore[assignment]
    FastAPIInstrumentor = None  # type: ignore[assignment]
    Resource = None  # type: ignore[assignment]
    TracerProvider = None  # type: ignore[assignment]
    BatchSpanProcessor = None  # type: ignore[assignment]


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1)
    system: str | None = None


class ChatResponse(BaseModel):
    response: str
    model: str
    langfuse_enabled: bool
    tempo_tracing_enabled: bool


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def langfuse_handler() -> Any:
    if CallbackHandler is None:
        return None
    host = env("LANGFUSE_HOST")
    public_key = env("LANGFUSE_PUBLIC_KEY")
    secret_key = env("LANGFUSE_SECRET_KEY")
    if not host or not public_key or not secret_key:
        return None
    return CallbackHandler(host=host, public_key=public_key, secret_key=secret_key)


def env_bool(name: str, default: bool = False) -> bool:
    value = env(name)
    if not value:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def tempo_tracing_enabled() -> bool:
    return env_bool("TEMPO_TRACING_ENABLED") and bool(env("OTEL_EXPORTER_OTLP_ENDPOINT"))


def configure_tracing(app: FastAPI) -> None:
    if not tempo_tracing_enabled():
        return
    if not all([trace, OTLPSpanExporter, FastAPIInstrumentor, Resource, TracerProvider, BatchSpanProcessor]):
        return

    endpoint = env("OTEL_EXPORTER_OTLP_ENDPOINT")
    service_name = env("OTEL_SERVICE_NAME", "agent-chatbot")
    insecure = env_bool("OTEL_EXPORTER_OTLP_INSECURE", True)
    provider = TracerProvider(
        resource=Resource.create(
            {
                "service.name": service_name,
                "service.namespace": "offline-k3s",
            }
        )
    )
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=insecure)))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="/healthz,/readyz")


def tracer() -> Any:
    if not tempo_tracing_enabled() or trace is None:
        return None
    return trace.get_tracer("agent-chatbot")


def backend_host(url: str) -> str:
    parsed = urlparse(url)
    return parsed.netloc or parsed.path.split("/", 1)[0]


def chat_model() -> ChatOpenAI:
    return ChatOpenAI(
        base_url=env("VLLM_BASE_URL", "http://vllm.vllm.svc.cluster.local:8000/v1"),
        api_key=env("VLLM_API_KEY", "EMPTY"),
        model=env("VLLM_MODEL", "local-model"),
        temperature=float(env("VLLM_TEMPERATURE", "0.2")),
    )


app = FastAPI(title="agent-chatbot", version="0.1.0")
configure_tracing(app)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ready"}


@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    messages = []
    if request.system:
        messages.append(SystemMessage(content=request.system))
    messages.append(HumanMessage(content=request.message))

    handler = langfuse_handler()
    config = {"callbacks": [handler]} if handler else {}
    model_name = env("VLLM_MODEL", "local-model")
    base_url = env("VLLM_BASE_URL", "http://vllm.vllm.svc.cluster.local:8000/v1")
    current_tracer = tracer()
    context = (
        current_tracer.start_as_current_span(
            "agent.chat.model_invoke",
            attributes={
                "llm.model": model_name,
                "llm.backend.host": backend_host(base_url),
                "langfuse.enabled": handler is not None,
                "request.has_system_prompt": request.system is not None,
            },
        )
        if current_tracer
        else nullcontext()
    )
    with context:
        result = chat_model().invoke(messages, config=config)

    return ChatResponse(
        response=str(result.content),
        model=model_name,
        langfuse_enabled=handler is not None,
        tempo_tracing_enabled=tempo_tracing_enabled(),
    )
