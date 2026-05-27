"""runner result exporter 단위 테스트."""

import json

import pytest

from exporters.result_exporter import (
    build_failure_result,
    build_success_result,
    write_result,
)


# 시나리오 1. source 실패가 있으면 부분 성공 result payload를 만든다.
@pytest.mark.unit
def test_build_success_result__source_has_failure__returns_partial_success():
    # Given: 일부 source 실패가 포함된 source stats와 top item을 준비한다.
    source_stats = {"youtube": {"used": 1, "failed": 1}}
    items = [{"title": "AI 뉴스", "url": "https://example.com", "category": "AI"}]

    # When: 성공 result payload를 만든다.
    result = build_success_result(
        job_id="job-1",
        started_at="2026-05-27T00:00:00+00:00",
        report_path="data/reports/report.md",
        meta_path="data/meta/report.meta.json",
        source_stats=source_stats,
        items=items,
        warnings=["youtube 수집 실패"],
    )

    # Then: status는 partial_success가 되고 Swift가 읽을 주요 필드가 포함된다.
    assert result["status"] == "partial_success"
    assert result["reportPath"] == "data/reports/report.md"
    assert result["metaPath"] == "data/meta/report.meta.json"
    assert result["topItems"][0]["title"] == "AI 뉴스"


# 시나리오 2. 실패 result payload를 JSON 파일로 기록한다.
@pytest.mark.unit
def test_write_result__failure_payload__writes_json_file(tmp_path):
    # Given: 실패 result payload와 저장 경로를 준비한다.
    result_path = tmp_path / "result.json"
    payload = build_failure_result(
        "job-1",
        "2026-05-27T00:00:00+00:00",
        RuntimeError("boom"),
    )

    # When: result exporter가 파일에 기록한다.
    write_result(str(result_path), payload)

    # Then: Swift가 읽을 수 있는 JSON 파일이 생성된다.
    written = json.loads(result_path.read_text(encoding="utf-8"))
    assert written["status"] == "failed"
    assert written["errorCode"] == "E_RUNNER_EXCEPTION"
    assert written["errorMessage"] == "boom"
