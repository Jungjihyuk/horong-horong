"""뉴스 source collector 단위 테스트."""

from __future__ import annotations

import pytest

from connectors.collector import collect_sources
from tracing.trace_writer import TraceWriter


class FakeConnector:
    def __init__(self, items: list[dict] | None = None, error: Exception | None = None):
        self._items = items or []
        self._error = error

    def collect(self) -> list[dict]:
        if self._error:
            raise self._error
        return self._items


# 시나리오 1. collector는 활성 source를 수집하고 runner용 통계를 만든다.
@pytest.mark.unit
def test_collect_sources__active_source__returns_items_and_stats():
    # Given: 수집 성공 connector와 로그 기록 리스트를 준비한다.
    sources = [{"type": "youtube", "enabled": True}]
    items = [{"title": "뉴스", "url": "https://example.com"}]
    logs: list[str] = []

    def connector_factory(source: dict, max_items: int) -> FakeConnector:
        return FakeConnector(items=items)

    # When: collector가 활성 source를 수집한다.
    result = collect_sources(
        sources,
        max_items=10,
        log_fn=logs.append,
        connector_factory=connector_factory,
    )

    # Then: 수집 항목과 source별 성공 통계가 반환된다.
    assert result.items == items
    assert result.source_stats == {
        "youtube": {"fetched": 1, "used": 1, "failed": 0}
    }
    assert result.warnings == []
    assert logs == ["Collecting from youtube...", "  youtube: 1 items"]


# 시나리오 2. collector는 비활성 source를 수집하지 않고 건너뛴다.
@pytest.mark.unit
def test_collect_sources__disabled_source__skips_source():
    # Given: disabled source와 호출되면 실패하는 connector factory를 준비한다.
    sources = [{"type": "youtube", "enabled": False}]
    logs: list[str] = []

    def connector_factory(source: dict, max_items: int) -> FakeConnector:
        raise AssertionError("disabled source should not create connector")

    # When: collector가 source 목록을 처리한다.
    result = collect_sources(
        sources,
        max_items=10,
        log_fn=logs.append,
        connector_factory=connector_factory,
    )

    # Then: 비활성 source는 항목, 통계, 경고를 만들지 않는다.
    assert result.items == []
    assert result.source_stats == {}
    assert result.warnings == []
    assert logs == []


# 시나리오 3. 개별 source 수집 실패는 전체 수집을 중단하지 않고 warning으로 남긴다.
@pytest.mark.unit
def test_collect_sources__connector_failure__records_warning_and_failed_stats():
    # Given: collect()에서 실패하는 connector와 로그 기록 리스트를 준비한다.
    sources = [{"type": "youtube", "enabled": True}]
    logs: list[str] = []

    def connector_factory(source: dict, max_items: int) -> FakeConnector:
        return FakeConnector(error=RuntimeError("boom"))

    # When: collector가 실패하는 source를 수집한다.
    result = collect_sources(
        sources,
        max_items=10,
        log_fn=logs.append,
        connector_factory=connector_factory,
    )

    # Then: 실패 통계와 사용자에게 전달할 warning이 기록된다.
    assert result.items == []
    assert result.source_stats == {"youtube": {"fetched": 0, "used": 0, "failed": 1}}
    assert result.warnings == ["youtube 수집 실패: boom"]
    assert logs == ["Collecting from youtube...", "  youtube ERROR: boom"]


# 시나리오 4. collector는 source별 수집 성능을 trace JSONL 이벤트로 남긴다.
@pytest.mark.unit
def test_collect_sources__trace_enabled__writes_connector_events(tmp_path):
    # Given: trace writer와 수집 성공 connector를 준비한다.
    trace_path = tmp_path / "trace.jsonl"
    trace = TraceWriter(str(trace_path), run_id="job-1")
    sources = [{"type": "youtube", "enabled": True}]
    items = [{"title": "뉴스", "url": "https://example.com"}]

    def connector_factory(source: dict, max_items: int) -> FakeConnector:
        return FakeConnector(items=items)

    # When: trace가 켜진 상태로 collector가 source를 수집한다.
    collect_sources(
        sources,
        max_items=10,
        log_fn=lambda message: None,
        trace=trace,
        connector_factory=connector_factory,
    )
    trace.close()

    # Then: connector 시작/완료 이벤트가 source_type과 count를 포함해 기록된다.
    import json

    events = [
        json.loads(line)
        for line in trace_path.read_text(encoding="utf-8").splitlines()
    ]
    assert [event["event"] for event in events] == [
        "connector_started",
        "connector_completed",
    ]
    assert events[0]["payload"] == {"source_type": "youtube", "max_items": 10}
    assert events[1]["stage"] == "collect"
    assert events[1]["payload"] == {
        "source_type": "youtube",
        "fetched": 1,
        "used": 1,
        "failed": 0,
        "max_items": 10,
    }
