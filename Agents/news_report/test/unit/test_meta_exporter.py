"""리포트 meta exporter 단위 테스트."""

from datetime import datetime, timezone

import pytest

from contracts.research_artifact import (
    CategoryAssignment,
    CategoryDefinition,
    CategoryTaxonomy,
    RelevanceJudgment,
    ReportContent,
    SourceCandidate,
    SourceInsight,
)
from exporters.meta_exporter import build_artifact_report_meta, build_report_meta
from ontology import NewsCategory, NewsOntology
from patterns.research.result import ResearchResult


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


# 시나리오 2. research artifact 묶음을 후속 분석용 meta payload로 생성한다.
@pytest.mark.unit
def test_build_artifact_report_meta__research_result__includes_artifacts():
    # Given: 리포트 생성에 사용된 research artifact 묶음을 준비한다.
    candidate = SourceCandidate(
        candidate_id="candidate-1",
        item_id="item-1",
        source_type="google_news",
        title="AI 뉴스",
        url="https://example.com",
        relevance_score=0.9,
        threshold=0.7,
        matched_keywords=["AI"],
        selected_reason="AI를 직접 다룬다.",
    )
    taxonomy = CategoryTaxonomy(
        taxonomy_id="taxonomy-ai",
        version="1",
        generated_from_keywords=["AI"],
        method="rule",
        categories=[
            CategoryDefinition(
                category_id="category-ai",
                name="AI",
                description="AI 소식",
                keywords=["AI"],
            )
        ],
    )
    assignment = CategoryAssignment(
        candidate_id=candidate.candidate_id,
        category_id="category-ai",
        category_name="AI",
        confidence=0.8,
        reason="키워드 기준으로 분류했다.",
        method="rule",
        taxonomy_id=taxonomy.taxonomy_id,
        taxonomy_version=taxonomy.version,
    )
    insight = SourceInsight(
        source_insight_id="source-insight-1",
        candidate_id=candidate.candidate_id,
        category_id="category-ai",
        summary="AI agent 도입이 늘고 있다.",
        key_points=["도입 증가"],
        importance_score=0.8,
        why_it_matters="AI 트렌드 파악에 중요하다.",
    )
    research_result = ResearchResult(
        relevance_judgments=[
            RelevanceJudgment(
                item_id="item-1",
                is_relevant=True,
                score=0.9,
                threshold=0.7,
                matched_keywords=["AI"],
                reason="AI를 직접 다루므로 관련성이 높다.",
            )
        ],
        source_candidates=[candidate],
        category_taxonomy=taxonomy,
        category_assignments=[assignment],
        source_insights=[insight],
        report_content=ReportContent(
            report_id="report-1",
            title="뉴스 큐레이션 리포트",
            generated_at="2026-05-28T00:00:00Z",
            interest_keywords=["AI"],
        ),
    )

    # When: artifact 기반 meta payload를 만든다.
    meta = build_artifact_report_meta(
        job_id="job-1",
        report_date="2026-05-28",
        generated_at=datetime(2026, 5, 28, 1, 2, tzinfo=timezone.utc),
        report_path="data/reports/report.md",
        research_result=research_result,
        source_stats={"google_news": {"used": 1, "failed": 0}},
        warnings=[],
    )

    # Then: meta에는 topItems와 researchArtifacts 원본 구조가 함께 포함된다.
    assert meta["itemCount"] == 1
    assert meta["categoryCounts"] == {"AI": 1}
    assert meta["topItems"][0]["headline"] == "AI agent 도입이 늘고 있다."
    assert meta["researchArtifacts"]["sourceCandidates"][0]["candidate_id"] == "candidate-1"
