"""Deep research trace writer 단위 테스트."""

import json

import pytest

from tracing.trace_writer import TraceWriter


# 시나리오 1. TraceWriter는 분석 가능한 구조화 이벤트를 JSONL 한 줄로 기록한다.
@pytest.mark.unit
def test_trace_writer__stage_completed__writes_jsonl_event(tmp_path):
    # Given: run_id와 pattern이 고정된 trace writer를 준비한다.
    trace_path = tmp_path / "trace.jsonl"
    writer = TraceWriter(
        trace_path=str(trace_path),
        run_id="job-1",
        pattern="news_report_v1",
        pattern_version="0.1.0",
    )

    # When: stage 완료 이벤트와 분석용 payload를 기록한다.
    event = writer.write(
        "stage_completed",
        stage="collect",
        duration_ms=1234,
        input_count=20,
        output_count=18,
    )
    writer.close()

    # Then: JSONL 이벤트에는 공통 필드와 payload가 함께 남는다.
    line = trace_path.read_text(encoding="utf-8").strip()
    parsed = json.loads(line)
    assert event.event == "stage_completed"
    assert parsed["run_id"] == "job-1"
    assert parsed["event"] == "stage_completed"
    assert parsed["pattern"] == "news_report_v1"
    assert parsed["pattern_version"] == "0.1.0"
    assert parsed["stage"] == "collect"
    assert parsed["duration_ms"] == 1234
    assert parsed["payload"] == {"input_count": 20, "output_count": 18}
    assert "timestamp" in parsed


# 시나리오 2. TraceWriter가 닫힌 뒤에는 trace 이벤트를 추가로 기록하지 않는다.
@pytest.mark.unit
def test_trace_writer__closed_writer__raises_value_error(tmp_path):
    # Given: 이미 닫힌 trace writer를 준비한다.
    trace_path = tmp_path / "trace.jsonl"
    writer = TraceWriter(trace_path=str(trace_path), run_id="job-1")
    writer.close()

    # When / Then: 닫힌 writer에 이벤트를 쓰면 ValueError를 발생시킨다.
    with pytest.raises(ValueError):
        writer.write("run_completed")
