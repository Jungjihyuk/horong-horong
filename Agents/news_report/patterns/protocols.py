"""
<행동 계약>
pattern 구현체가 따라야 하는 실행 계약.
패턴이 어떤 메서드를 가져야 하는가.
패턴 구현체가 지켜야 하는 실행 인커페이스 계약.
"""

from __future__ import annotations

from typing import Protocol

from patterns.context import PipelineContext
from patterns.result import PatternResult


class PipelinePattern(Protocol):
    """제품 기능 단위 pipeline pattern 계약."""

    name: str
    version: str

    def run(self, context: PipelineContext) -> PatternResult:
        """pattern을 실행하고 runner가 사용할 결과를 반환한다."""
