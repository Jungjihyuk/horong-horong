"""provider metrics 비교 eval 단위 테스트."""

from __future__ import annotations

import json
from pathlib import Path
from typing import cast

import pytest

from evals.compare_provider_metrics import (
    compare_provider_metrics,
    main,
    render_table,
)


# 시나리오 1. 여러 provider metrics JSON을 비교 가능한 rows로 변환한다.
@pytest.mark.unit
def test_compare_provider_metrics__metrics_files__returns_provider_rows(
    tmp_path: Path,
):
    # Given: Ollama와 Codex metrics JSON 파일을 준비한다.
    ollama_path = write_metrics(
        tmp_path / "ollama.json",
        provider="ollama",
        job_id="local-ollama-all-sources-001",
        source_candidates=6,
        source_insights=6,
        trend_insights=3,
        warning_count=0,
        provider_calls=18,
        provider_failures=0,
        stage_failures=0,
        avg_latency_ms=9436,
    )
    codex_path = write_metrics(
        tmp_path / "codex.json",
        provider="codex",
        job_id="local-codex-all-sources-001",
        source_candidates=5,
        source_insights=4,
        trend_insights=2,
        warning_count=2,
        provider_calls=16,
        provider_failures=1,
        stage_failures=1,
        avg_latency_ms=8120,
    )

    # When: provider metrics 비교 eval을 실행한다.
    comparison = compare_provider_metrics([ollama_path, codex_path])

    # Then: provider별 핵심 지표 row와 대표 bestBy 값이 계산된다.
    rows = cast(list[dict[str, object]], comparison["providers"])
    assert [row["provider"] for row in rows] == ["ollama", "codex"]
    assert rows[0]["sourceCandidates"] == 6
    assert rows[0]["successRate"] == 1.0
    assert rows[1]["providerFailures"] == 1
    assert comparison["bestBy"] == {
        "mostSourceCandidates": "ollama",
        "mostSourceInsights": "ollama",
        "mostTrendInsights": "ollama",
        "fewestWarnings": "ollama",
        "fewestProviderFailures": "ollama",
        "lowestAvgLatencyMs": "codex",
    }


# 시나리오 2. 비교 결과는 사람이 보기 쉬운 Markdown table로 출력할 수 있다.
@pytest.mark.unit
def test_render_table__comparison__includes_provider_metric_columns(tmp_path: Path):
    # Given: provider 비교 결과를 준비한다.
    metrics_path = write_metrics(
        tmp_path / "ollama.json",
        provider="ollama",
        job_id="local-ollama-all-sources-001",
        source_candidates=6,
        source_insights=6,
        trend_insights=3,
        warning_count=0,
        provider_calls=18,
        provider_failures=0,
        stage_failures=0,
        avg_latency_ms=9436,
    )
    comparison = compare_provider_metrics([metrics_path])

    # When: table 형식으로 렌더링한다.
    table = render_table(comparison)

    # Then: provider와 핵심 지표 컬럼이 포함된다.
    assert "| provider | candidates" in table
    assert "| ollama   | 6" in table
    assert "9436" in table


# 시나리오 3. CLI는 table을 출력하고 비교 JSON을 파일로 저장한다.
@pytest.mark.unit
def test_compare_provider_metrics_cli__output_path__writes_comparison_json(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
):
    # Given: metrics JSON과 output 경로를 준비한다.
    metrics_path = write_metrics(
        tmp_path / "ollama.json",
        provider="ollama",
        job_id="local-ollama-all-sources-001",
        source_candidates=6,
        source_insights=6,
        trend_insights=3,
        warning_count=0,
        provider_calls=18,
        provider_failures=0,
        stage_failures=0,
        avg_latency_ms=9436,
    )
    output_path = tmp_path / "comparison.json"

    # When: CLI entrypoint를 실행한다.
    exit_code = main(
        [
            "--metrics",
            str(metrics_path),
            "--output",
            str(output_path),
        ]
    )

    # Then: table stdout과 comparison JSON 파일이 생성된다.
    assert exit_code == 0
    stdout = capsys.readouterr().out
    assert "provider" in stdout
    assert "ollama" in stdout
    comparison = cast(
        dict[str, object],
        json.loads(output_path.read_text(encoding="utf-8")),
    )
    assert len(cast(list[object], comparison["providers"])) == 1


def write_metrics(
    path: Path,
    *,
    provider: str,
    job_id: str,
    source_candidates: int,
    source_insights: int,
    trend_insights: int,
    warning_count: int,
    provider_calls: int,
    provider_failures: int,
    stage_failures: int,
    avg_latency_ms: int,
) -> Path:
    """테스트용 research_run_metrics JSON 파일을 쓴다."""
    payload = {
        "provider": provider,
        "jobId": job_id,
        "artifactCounts": {
            "sourceCandidates": source_candidates,
            "sourceInsights": source_insights,
            "insightBundles": max(1, trend_insights),
            "trendInsights": trend_insights,
        },
        "warningCount": warning_count,
        "providerCalls": provider_calls,
        "providerCompletions": provider_calls - provider_failures,
        "providerFailures": provider_failures,
        "stageFailures": stage_failures,
        "avgProviderLatencyMs": avg_latency_ms,
    }
    _ = path.write_text(json.dumps(payload), encoding="utf-8")
    return path
