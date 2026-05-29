"""research pattern 실행에 필요한 공통 context."""

from __future__ import annotations

from collections.abc import Callable
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Protocol

from ontology.models import NewsOntology
from providers.protocols import StructuredProvider
from tracing.events import TraceEventName


class TraceSink(Protocol):
    """research pattern이 필요로 하는 trace 기록 계약.
       trace 이벤트를 받아 기록하는 대상.
    """

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


@dataclass
class ResearchContext:
    """수집/정규화된 자료를 research artifact로 바꾸는 실행 context."""
    
    # 입력 데이터 
    items: list[dict[str, object]]
    interest_keywords: list[str]
    
    # 실행 도구
    provider: StructuredProvider
    log: Callable[[str], None]  # 문자열을 받아서 아무것도 반환하지 않는 함수
    trace: TraceSink | None = None
    
    # 입력 데이터
    ontology: NewsOntology | None = None
    relevance_threshold: float = 0.7
