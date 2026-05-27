"""Deep research 실행 흔적을 구조화 이벤트로 남기는 writer.

이 모듈은 사람이 읽는 실행 로그를 남기는 `tracing/run_logger.py`와 역할이 다르다.
프로그램이 다시 읽고 분석할 수 있는 JSONL 이벤트를 쓴다.

여기서 trace는 "어떤 run이 어떤 stage, provider 호출, validation, retry,
artifact write를 거쳐 어떤 결과에 도달했는지"를 따라갈 수 있게 남긴
구조화된 실행 기록이다.

TraceWriter의 소비자 
- deep research 구현자 
- 분석 스크립트 
- 성능 병목을 찾는 개발자
- provider/connector/stage 별 실패율과 지연 시간을 보는 도구

예시 이벤트:

    {"event": "stage_completed", "stage": "judge", "duration_ms": 4300}
    {"event": "artifact_written", "artifact": "report_run.json", "count": 1}
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from datetime import datetime, timezone
from typing import Any, TextIO

from tracing.events import TraceEvent, TraceEventName


class TraceWriter:
    """Deep research 실행 이벤트를 JSONL 파일에 append한다.

    TraceWriter는 이벤트를 평가하거나 분석하지 않는다. 호출자가 넘긴 stage,
    duration, count, score 같은 분석용 값을 `TraceEvent`로 검증한 뒤 JSONL 한 줄로
    저장한다.
    """

    def __init__(
        self,
        trace_path: str,
        run_id: str,
        pattern: str | None = None,
        pattern_version: str | None = None,
        auto_flush: bool = True,
    ):
        """TraceWriter를 생성하고 JSONL 파일을 append 모드로 연다.

        Args:
            trace_path: trace JSONL 파일 경로.
            run_id: 현재 뉴스 리포트 실행 ID. 보통 Swift 요청의 `jobId`를 쓴다.
            pattern: deep research pattern 이름. 예: `news_report_v1`.
            pattern_version: pattern 변경 추적용 버전 문자열.
            auto_flush: 이벤트를 쓸 때마다 즉시 flush할지 여부.
        """
        os.makedirs(os.path.dirname(os.path.abspath(trace_path)), exist_ok=True)
        self._file: TextIO = open(trace_path, "a", encoding="utf-8", buffering=1)
        self._run_id = run_id
        self._pattern = pattern
        self._pattern_version = pattern_version
        self._auto_flush = auto_flush
        self._closed = False

    def write(
        self,
        event: TraceEventName,
        *,
        stage: str | None = None,
        duration_ms: int | None = None,
        payload: Mapping[str, Any] | None = None,
        **payload_fields: Any,
    ) -> TraceEvent:
        """trace 이벤트를 JSONL 한 줄로 기록한다.

        Args:
            event: 이벤트 이름. `TraceEventName`에 정의된 값만 허용한다.
            stage: 이벤트가 속한 pipeline stage 이름.
            duration_ms: 이벤트가 측정한 소요 시간(ms).
            payload: 이벤트별 세부 분석 값.
            **payload_fields: payload에 추가할 간단한 key-value 값.

        Returns:
            파일에 기록한 `TraceEvent` 모델.
        """
        if self._closed:
            raise ValueError("TraceWriter is already closed.")

        merged_payload = dict(payload or {})
        merged_payload.update(payload_fields)

        trace_event = TraceEvent(
            timestamp=datetime.now(timezone.utc),
            run_id=self._run_id,
            event=event,
            pattern=self._pattern,
            pattern_version=self._pattern_version,
            stage=stage,
            duration_ms=duration_ms,
            payload=merged_payload,
        )
        self._file.write(trace_event.model_dump_json(exclude_none=True) + "\n")
        if self._auto_flush:
            self._file.flush()
        return trace_event

    def flush(self) -> None:
        """아직 버퍼에 남은 trace 이벤트를 파일에 쓴다."""
        if not self._closed:
            self._file.flush()

    def close(self) -> None:
        """trace 파일 핸들을 닫는다."""
        if not self._closed:
            self._file.close()
            self._closed = True

    def __enter__(self) -> "TraceWriter":
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.close()
