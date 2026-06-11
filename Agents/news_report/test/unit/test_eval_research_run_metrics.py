"""research run metrics eval 단위 테스트."""

from __future__ import annotations

import json
from pathlib import Path
from typing import cast

import pytest

from evals.research_run_metrics import (
    main,
    research_run_metrics,
    structured_output_reliability,
)


# 시나리오 1. meta와 trace 파일에서 provider 비교용 정량 지표를 계산한다.
@pytest.mark.unit
def test_research_run_metrics__meta_and_trace__returns_artifact_and_provider_metrics(
    tmp_path: Path,
):
    # Given: artifact meta와 provider trace JSONL을 준비한다.
    meta_path = tmp_path / "report.meta.json"
    trace_path = tmp_path / "trace.jsonl"
    _ = meta_path.write_text(
        json.dumps(
            {
                "jobId": "job-1",
                "reportDate": "2026-05-29",
                "reportPath": "reports/2026-05-29.md",
                "itemCount": 2,
                "researchArtifacts": {
                    "sourceItems": [{"item_id": "item-1"}],
                    "extractedArticles": [{"item_id": "item-1"}],
                    "keywordMatches": [],
                    "relevanceJudgments": [{"item_id": "item-1"}],
                    "sourceCandidates": [{"candidate_id": "candidate-1"}],
                    "categoryAssignments": [{"candidate_id": "candidate-1"}],
                    "sourceInsights": [{"source_insight_id": "source-insight-1"}],
                    "insightBundles": [{"bundle_id": "bundle-1"}],
                    "keywordInsights": [{"keyword_insight_id": "keyword-1"}],
                    "trendInsights": [],
                    "reportContent": {"report_id": "report-1"},
                    "categoryTaxonomy": {"taxonomy_id": "taxonomy-1"},
                },
                "sourceStats": {"google_news": {"fetched": 2, "used": 1}},
                "warnings": ["trend insight 생성 실패"],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    trace_events = [
        {
            "event": "provider_started",
            "payload": {
                "operation": "structured_output",
                "schema": "RelevanceJudgment",
            },
        },
        {
            "event": "provider_completed",
            "duration_ms": 100,
            "payload": {
                "operation": "structured_output",
                "schema": "RelevanceJudgment",
            },
        },
        {
            "event": "provider_started",
            "payload": {
                "operation": "structured_output",
                "schema": "SourceInsight",
            },
        },
        {
            "event": "provider_failed",
            "duration_ms": 300,
            "payload": {
                "operation": "structured_output",
                "schema": "SourceInsight",
            },
        },
        {
            "event": "stage_failed",
            "payload": {"schema": "SourceInsight"},
        },
    ]
    _ = trace_path.write_text(
        "\n".join(json.dumps(event, ensure_ascii=False) for event in trace_events),
        encoding="utf-8",
    )

    # When: offline research run metrics eval을 계산한다.
    metrics = research_run_metrics(meta_path, trace_path)

    # Then: artifact 완성도와 provider structured output 지표가 함께 반환된다.
    assert metrics["jobId"] == "job-1"
    assert metrics["warningCount"] == 1
    assert metrics["providerCalls"] == 2
    assert metrics["providerCompletions"] == 1
    assert metrics["providerFailures"] == 1
    assert metrics["stageFailures"] == 1
    assert metrics["avgProviderLatencyMs"] == 200
    assert metrics["schemaCounts"] == {
        "RelevanceJudgment": 1,
        "SourceInsight": 1,
    }
    assert metrics["repairRate"] is None
    assert metrics["artifactCounts"] == {
        "sourceItems": 1,
        "extractedArticles": 1,
        "keywordMatches": 0,
        "relevanceJudgments": 1,
        "sourceCandidates": 1,
        "categoryAssignments": 1,
        "sourceInsights": 1,
        "insightBundles": 1,
        "keywordInsights": 1,
        "trendInsights": 0,
        "reportContent": 1,
        "categoryTaxonomy": 1,
    }


# 시나리오 2. CLI 실행 시 metrics JSON을 output 파일로 저장한다.
@pytest.mark.unit
def test_research_run_metrics_cli__output_path__writes_metrics_json(tmp_path: Path):
    # Given: 최소 meta 파일과 output 경로를 준비한다.
    meta_path = tmp_path / "report.meta.json"
    output_path = tmp_path / "metrics.json"
    _ = meta_path.write_text(
        json.dumps(
            {
                "jobId": "job-1",
                "reportDate": "2026-05-29",
                "reportPath": "reports/2026-05-29.md",
                "itemCount": 0,
                "researchArtifacts": {},
                "warnings": [],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    # When: CLI entrypoint를 output 파일 옵션으로 실행한다.
    exit_code = main(
        [
            "--meta",
            str(meta_path),
            "--output",
            str(output_path),
        ]
    )

    # Then: metrics JSON 파일이 생성된다.
    assert exit_code == 0
    metrics = cast(
        dict[str, object],
        json.loads(output_path.read_text(encoding="utf-8")),
    )
    assert metrics["jobId"] == "job-1"
    assert metrics["providerCalls"] == 0


# 시나리오 3. repair_attempted 필드가 있을 때 1차/복구/실패 비율을 분해한다.
@pytest.mark.unit
def test_structured_output_reliability__mixed_outcomes__computes_three_rates():
    # Given: 1차 성공 2건, repair 복구 1건, 최종 실패 1건의 trace 이벤트.
    events = [
        {"event": "provider_completed", "payload": {"repair_attempted": False}},
        {"event": "provider_completed", "payload": {"repair_attempted": False}},
        {"event": "provider_completed", "payload": {"repair_attempted": True}},
        {"event": "provider_failed", "payload": {}},
    ]

    # When: 구조화 출력 신뢰도 지표를 계산한다.
    reliability = structured_output_reliability(events)

    # Then: 총 4회 중 1차 성공률 0.5, repair 복구율 0.5, 최종 실패율 0.25.
    assert reliability["totalCalls"] == 4
    assert reliability["firstPassSuccesses"] == 2
    assert reliability["repairedSuccesses"] == 1
    assert reliability["failures"] == 1
    assert reliability["firstPassRate"] == 0.5
    assert reliability["repairRecoveryRate"] == 0.5
    assert reliability["finalFailureRate"] == 0.25


# 시나리오 4. repair_attempted 필드가 없으면 repair 의존 비율은 None이다.
@pytest.mark.unit
def test_structured_output_reliability__no_repair_field__repair_rates_none():
    # Given: repair_attempted 필드가 없는 완료 2건과 실패 1건.
    events = [
        {"event": "provider_completed", "payload": {"schema": "RelevanceJudgment"}},
        {"event": "provider_completed", "payload": {"schema": "RelevanceJudgment"}},
        {"event": "provider_failed", "payload": {"schema": "RelevanceJudgment"}},
    ]

    # When: 구조화 출력 신뢰도 지표를 계산한다.
    reliability = structured_output_reliability(events)

    # Then: repair 구분 불가 → 관련 비율은 None, 최종 실패율만 계산된다.
    assert reliability["totalCalls"] == 3
    assert reliability["firstPassSuccesses"] == 0
    assert reliability["repairedSuccesses"] == 0
    assert reliability["failures"] == 1
    assert reliability["firstPassRate"] is None
    assert reliability["repairRecoveryRate"] is None
    assert reliability["finalFailureRate"] == pytest.approx(1 / 3)


# 시나리오 5. 호출이 전혀 없으면 모든 비율이 None이다.
@pytest.mark.unit
def test_structured_output_reliability__no_calls__all_rates_none():
    # Given: provider 호출 이벤트가 없는 trace.
    events = [{"event": "stage_started", "payload": {}}]

    # When: 구조화 출력 신뢰도 지표를 계산한다.
    reliability = structured_output_reliability(events)

    # Then: 분모가 0 → 모든 비율 None.
    assert reliability["totalCalls"] == 0
    assert reliability["firstPassRate"] is None
    assert reliability["repairRecoveryRate"] is None
    assert reliability["finalFailureRate"] is None
