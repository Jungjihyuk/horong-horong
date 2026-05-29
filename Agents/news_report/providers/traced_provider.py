"""provider structured output 호출을 trace 이벤트로 기록하는 wrapper."""

from __future__ import annotations

from time import perf_counter
from collections.abc import Mapping
from typing import Protocol

from pydantic import BaseModel

from providers.protocols import ProviderOptions, StructuredModel, StructuredProvider
from tracing.events import TraceEventName


class TraceSink(Protocol):
    """provider wrapper가 필요로 하는 trace 기록 계약."""

    def write(
        self,
        event: TraceEventName,
        *,
        stage: str | None = None,
        duration_ms: int | None = None,
        payload: Mapping[str, object] | None = None,
        **payload_fields: object,
    ) -> object:
        """trace 이벤트를 기록한다."""
        ...


class TracedStructuredProvider:
    """StructuredProvider 호출 전후를 trace에 남기는 얇은 decorator."""

    def __init__(
        self,
        provider: StructuredProvider,
        trace: TraceSink,
        provider_name: str,
    ):
        self._provider: StructuredProvider = provider
        self._trace: TraceSink = trace
        self._provider_name: str = provider_name

    def run(self, prompt: str) -> str:
        """기존 TextProvider 계약과 호환되는 텍스트 생성 메서드."""
        return self._provider.run(prompt)

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        """내부 provider의 텍스트 생성을 그대로 위임한다."""
        return self._provider.generate_text(prompt, options=options)

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        """structured output 생성 시작/성공/실패를 trace 이벤트로 기록한다."""
        started_at = perf_counter()
        payload = self._payload_for(prompt, schema_model, options)
        _ = self._trace.write(
            "provider_started",
            stage="provider.generate_json",
            payload=payload,
        )

        try:
            result = self._provider.generate_json(prompt, schema_model, options=options)
        except Exception as error:
            _ = self._trace.write(
                "provider_failed",
                stage="provider.generate_json",
                duration_ms=elapsed_ms(started_at),
                payload={
                    **payload,
                    "error_type": type(error).__name__,
                    "error_message": str(error)[:500],
                },
            )
            raise

        _ = self._trace.write(
            "provider_completed",
            stage="provider.generate_json",
            duration_ms=elapsed_ms(started_at),
            payload={
                **payload,
                "result_model": result.__class__.__name__,
            },
        )
        return result

    def _payload_for(
        self,
        prompt: str,
        schema_model: type[BaseModel],
        options: ProviderOptions | None,
    ) -> dict[str, object]:
        payload: dict[str, object] = {
            "provider": self._provider_name,
            "provider_class": self._provider.__class__.__name__,
            "operation": "structured_output",
            "schema": schema_model.__name__,
            "prompt_chars": len(prompt),
        }
        if options is not None:
            payload["options"] = {
                key: value
                for key, value in {
                    "temperature": options.temperature,
                    "num_ctx": options.num_ctx,
                    "top_p": options.top_p,
                }.items()
                if value is not None
            }
        return payload


def elapsed_ms(started_at: float) -> int:
    """perf_counter 기준 elapsed milliseconds."""
    return int((perf_counter() - started_at) * 1000)
