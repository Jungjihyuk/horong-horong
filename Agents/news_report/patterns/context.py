"""pattern 실행에 필요한 공통 context."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from contracts.news_job_request import NewsJobRequest
from providers.protocols import TextProvider
from tracing.trace_writer import TraceWriter


@dataclass
class PipelineContext:
    """pipeline pattern이 stage 실행 중 공유하는 실행 context."""

    request: NewsJobRequest
    provider: TextProvider
    log: Callable[[str], None]
    step: Callable[[str], None]
    trace: TraceWriter | None
    started_at: str
    # 이미 채택했던 URL 을 무시하고 다시 수집한다. 과거 리포트를 다시 만들거나
    # 기록이 잘못됐을 때만 쓴다(`runner.py --ignore-seen`).
    ignore_seen: bool = False
