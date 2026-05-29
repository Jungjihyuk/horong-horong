"""LLM/text provider 구현체가 지켜야 하는 계약."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, TypeVar, runtime_checkable

from pydantic import BaseModel


StructuredModel = TypeVar("StructuredModel", bound=BaseModel)


@dataclass(frozen=True)
class ProviderOptions:
    """provider 호출에 공통으로 전달할 생성 옵션."""

    temperature: float | None = None
    num_ctx: int | None = None
    top_p: float | None = None


@runtime_checkable
class TextProvider(Protocol):
    """prompt를 받아 텍스트 응답을 반환하는 provider 계약.

    CLI provider, HTTP 기반 provider, 로컬 모델 provider 모두 이 메서드만 제공하면
    runner와 요약/분류 로직에서 같은 방식으로 사용할 수 있다.
    """

    def run(self, prompt: str) -> str:
        """prompt를 실행하고 텍스트 응답을 반환한다."""
        ...

@runtime_checkable
class StructuredProvider(TextProvider, Protocol):
    """Pydantic schema에 맞는 구조화 응답을 생성하는 provider 계약."""

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        """prompt를 실행하고 텍스트 응답을 반환한다."""
        ...

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        """prompt를 실행하고 Pydantic 모델로 검증된 구조화 응답을 반환한다."""
        ...
