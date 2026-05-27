"""LLM/text provider 구현체가 지켜야 하는 최소 계약."""

from __future__ import annotations

from typing import Protocol


class TextProvider(Protocol):
    """prompt를 받아 텍스트 응답을 반환하는 provider 계약.

    CLI provider, HTTP 기반 provider, 로컬 모델 provider 모두 이 메서드만 제공하면
    runner와 요약/분류 로직에서 같은 방식으로 사용할 수 있다.
    """

    def run(self, prompt: str) -> str:
        """prompt를 실행하고 텍스트 응답을 반환한다."""
