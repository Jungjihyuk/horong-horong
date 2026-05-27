"""리포트 meta exporter 단위 테스트."""

from datetime import datetime, timezone

import pytest

from exporters.meta_exporter import build_report_meta
from ontology import NewsCategory, NewsOntology


# 시나리오 1. 리포트와 후속 분석이 읽을 meta payload를 생성한다.
@pytest.mark.unit
def test_build_report_meta__summarized_items__returns_meta_payload():
    # Given: 요약된 item, ontology, 카테고리 집계를 준비한다.
    ontology = NewsOntology(
        categories=[NewsCategory(label="AI", keywords=["AI"], description="")]
    )
    items = [
        {
            "title": "AI 뉴스",
            "url": "https://example.com",
            "category": "AI",
            "sourceType": "google_news",
            "importanceScore": 90,
            "publishedAt": "2026-05-27T00:00:00Z",
            "headline": "AI 에이전트 도입 증가",
        }
    ]

    # When: meta payload를 만든다.
    meta = build_report_meta(
        job_id="job-1",
        report_date="2026-05-27",
        generated_at=datetime(2026, 5, 27, 1, 2, tzinfo=timezone.utc),
        report_path="data/reports/report.md",
        items=items,
        interest_keywords=["AI"],
        ontology=ontology,
        by_category={"AI": items},
        category_keywords={"AI": ["agent"]},
        category_trends={"AI": "AI 에이전트가 확산 중이다."},
        source_stats={"google_news": {"used": 1, "failed": 0}},
        warnings=[],
    )

    # Then: report path, ontology snapshot, top item 정보가 포함된다.
    assert meta["jobId"] == "job-1"
    assert meta["reportPath"] == "data/reports/report.md"
    assert meta["ontologySnapshot"] == [{"label": "AI", "keywords": ["AI"]}]
    assert meta["categoryCounts"] == {"AI": 1}
    assert meta["topItems"][0]["headline"] == "AI 에이전트 도입 증가"
