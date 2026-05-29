"""Trace JSONL에 기록할 구조화 이벤트의 데이터 계약을 정의한다.

`tracing/run_logger.py`가 사람이 읽는 문장형 로그를 남긴다면, 이 모듈의 모델은
deep research 구현자가 프로그램으로 다시 읽고 분석할 이벤트 형식을 정한다.

예를 들어 어떤 pattern이 실행됐는지, 어느 stage가 오래 걸렸는지, provider 호출이
성공했는지, 최종 report 품질 평가가 어땠는지 같은 값을 한 줄짜리 JSON 이벤트로
남길 때 그 공통 필드와 허용되는 event 이름을 이 파일에서 관리한다.

`tracing/trace_writer.py`는 여기서 정의한 모델을 받아 실제 JSONL 파일에 append하는
쓰기 담당이고, 이 파일은 "무엇을 어떤 모양으로 기록할지"를 표현하는 계약 담당이다.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


TraceEventName = Literal[
    "run_started",
    "run_completed",
    "run_failed",
    "stage_started",
    "stage_completed",
    "stage_failed",
    "connector_started",
    "connector_completed",
    "connector_failed",
    "provider_started",
    "provider_completed",
    "provider_failed",
    "artifact_written",
    "quality_evaluated",
]


class TraceEvent(BaseModel):
    """JSONL 한 줄로 기록되는 구조화 trace 이벤트.

    공통 필드는 고정하고, 이벤트별 세부 값은 `payload`에 담는다. 이렇게 두면
    deep research pattern이 늘어나도 TraceWriter의 기본 구조를 크게 바꾸지 않고
    병목, 실패율, 품질 평가 같은 분석용 값을 추가할 수 있다.
    """

    model_config = ConfigDict(
        extra="forbid",   # 분석용 데이터 이기 때문에 필드 오타나 잘못된 구조를 바로 잡기 위해
        strict=True,
        str_strip_whitespace=True,
    )

    timestamp: datetime
    run_id: str = Field(min_length=1)
    event: TraceEventName
    pattern: str | None = Field(default=None, min_length=1)
    pattern_version: str | None = Field(default=None, min_length=1)
    stage: str | None = Field(default=None, min_length=1)
    duration_ms: int | None = Field(default=None, ge=0)
    payload: dict[str, Any] = Field(default_factory=dict)
