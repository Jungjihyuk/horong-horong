"""Markdown renderer 단위 테스트."""

import pytest

from contracts.research_artifact import (
    InsightBundle,
    KeywordInsight,
    RelevanceJudgment,
    ReportContent,
    SourceCandidate,
    SourceInsight,
    TrendInsight,
)
from ontology import NewsCategory, NewsOntology
from patterns.research.result import ResearchResult
from renderers.markdown import render_artifact_markdown_report, render_markdown_report


# 시나리오 1. 정제된 리포트 데이터를 Markdown 문서로 변환한다.
@pytest.mark.unit
def test_render_markdown_report__categorized_items__includes_report_sections():
    # Given: 카테고리와 요약이 포함된 리포트 item을 준비한다.
    ontology = NewsOntology(
        categories=[NewsCategory(label="AI", keywords=["AI"], description="")]
    )
    items = [
        {
            "title": "AI 뉴스",
            "url": "https://example.com",
            "category": "AI",
            "importanceScore": 90,
            "headline": "AI 에이전트 시장이 확대되고 있다.",
            "bullets": ["기업 도입 사례 증가"],
        }
    ]

    # When: Markdown renderer를 실행한다.
    markdown = render_markdown_report(
        items=items,
        date_str="2026-05-27",
        generated_at="2026-05-27 10:00",
        interest_keywords=["AI"],
        source_stats={"google_news": {"used": 1, "failed": 0}},
        warnings=[],
        ontology=ontology,
        category_keywords={"AI": ["agent"]},
        category_trends={"AI": "AI 에이전트 도입이 늘고 있다."},
    )

    # Then: 기본 섹션, 카테고리, item 내용이 Markdown에 포함된다.
    assert "# 뉴스 큐레이션 리포트 - 2026-05-27" in markdown
    assert "## 수집 현황" in markdown
    assert "## AI" in markdown
    assert "🔑 키워드: agent" in markdown
    assert "[AI 뉴스](https://example.com)" in markdown
    assert "## 오늘의 액션 아이템" in markdown


# 시나리오 2. research artifact 묶음을 Markdown 리포트로 변환한다.
@pytest.mark.unit
def test_render_artifact_markdown_report__research_result__includes_artifact_sections():
    # Given: SourceCandidate부터 ReportContent까지 연결된 artifact 묶음을 준비한다.
    candidate = SourceCandidate(
        candidate_id="candidate-1",
        item_id="item-1",
        source_type="google_news",
        title="AI agent 뉴스",
        url="https://example.com/ai",
        relevance_score=0.9,
        threshold=0.7,
        matched_keywords=["AI agent"],
        selected_reason="AI agent를 직접 다룬다.",
    )
    source_insight = SourceInsight(
        source_insight_id="source-insight-1",
        candidate_id=candidate.candidate_id,
        category_id="category-ai",
        summary="AI agent가 개발 자동화를 돕는 흐름이 관찰된다.",
        key_points=["개발 자동화", "생산성 개선"],
        importance_score=0.84,
        why_it_matters="AI 개발 자동화 흐름을 이해하는 데 중요하다.",
    )
    bundle = InsightBundle(
        bundle_id="bundle-ai",
        bundle_type="category",
        title="AI 에이전트",
        source_insight_ids=[source_insight.source_insight_id],
        summary="AI agent 관련 소식 묶음",
        key_takeaways=["agent 활용 증가"],
        category_id="category-ai",
    )
    research_result = ResearchResult(
        relevance_judgments=[
            RelevanceJudgment(
                item_id="item-1",
                is_relevant=True,
                score=0.9,
                threshold=0.7,
                matched_keywords=["AI agent"],
                reason="AI agent를 직접 다루므로 관련성이 높다.",
            )
        ],
        source_candidates=[candidate],
        source_insights=[source_insight],
        insight_bundles=[bundle],
        keyword_insights=[
            KeywordInsight(
                keyword_insight_id="keyword-1",
                scope="bundle",
                scope_id=bundle.bundle_id,
                keywords=["agent", "자동화"],
            )
        ],
        trend_insights=[
            TrendInsight(
                trend_id="trend-1",
                scope="bundle",
                scope_id=bundle.bundle_id,
                title="AI agent 확산",
                summary="AI agent 활용이 늘고 있다.",
                trend_type="emerging",
                source_insight_ids=[source_insight.source_insight_id],
                confidence=0.7,
            )
        ],
        report_content=ReportContent(
            report_id="report-1",
            title="뉴스 큐레이션 리포트",
            generated_at="2026-05-28T00:00:00Z",
            interest_keywords=["AI agent"],
            bundle_ids=[bundle.bundle_id],
            keyword_insight_ids=["keyword-1"],
            trend_insight_ids=["trend-1"],
        ),
    )

    # When: artifact 기반 Markdown renderer를 실행한다.
    markdown = render_artifact_markdown_report(
        research_result=research_result,
        date_str="2026-05-28",
        generated_at="2026-05-28 10:00",
        interest_keywords=["AI agent"],
        source_stats={"google_news": {"used": 1, "failed": 0}},
        warnings=[],
    )

    # Then: bundle, keyword, trend, source insight 내용이 Markdown에 포함된다.
    assert "# 뉴스 큐레이션 리포트 - 2026-05-28" in markdown
    assert "## AI 에이전트" in markdown
    assert "🔑 키워드: agent, 자동화" in markdown
    assert "📈 트렌드: AI agent 활용이 늘고 있다." in markdown
    assert "[AI agent 뉴스](https://example.com/ai)" in markdown
