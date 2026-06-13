import os
from contextlib import nullcontext
from typing import Any

from fastapi import FastAPI
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

try:
    from langfuse.callback import CallbackHandler
except Exception:  # pragma: no cover - optional dependency integration
    CallbackHandler = None  # type: ignore[assignment]


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1)
    system: str | None = None


class ChatResponse(BaseModel):
    response: str
    model: str
    langfuse_enabled: bool


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


def chat_model() -> ChatOpenAI:
    return ChatOpenAI(
        base_url=env("VLLM_BASE_URL", "http://vllm.vllm.svc.cluster.local:8000/v1"),
        api_key=env("VLLM_API_KEY", "EMPTY"),
        model=env("VLLM_MODEL", "local-model"),
        temperature=float(env("VLLM_TEMPERATURE", "0.2")),
    )


app = FastAPI(title="agent-chatbot", version="0.1.0")


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
    context = nullcontext()
    with context:
        result = chat_model().invoke(messages, config=config)

    return ChatResponse(
        response=str(result.content),
        model=env("VLLM_MODEL", "local-model"),
        langfuse_enabled=handler is not None,
    )

