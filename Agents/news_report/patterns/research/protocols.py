"""research pattern 구현체가 따라야 하는 실행 계약."""

from __future__ import annotations

from typing import Protocol

from patterns.research.context import ResearchContext
from patterns.research.result import ResearchResult


class ResearchPattern(Protocol):
    """자료 분석 방법론 단위 pattern 계약."""

    name: str
    version: str

    def run(self, context: ResearchContext) -> ResearchResult:
        """research pattern을 실행하고 artifact 묶음을 반환한다."""
        ...
