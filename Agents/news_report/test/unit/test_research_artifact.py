"""Deep research artifact 계약 단위 테스트."""

import pytest
from pydantic import ValidationError

from contracts.research_artifact import (
    CategoryAssignment,
    CategoryDefinition,
    CategoryTaxonomy,
    ExtractedArticle,
    InsightBundle,
    KeywordInsight,
    KeywordMatch,
    ReportContent,
    RelevanceJudgment,
    SourceCandidate,
    SourceInsight,
    SourceItem,
    TrendInsight,
)


# 시나리오 1. 수집된 원본 항목은 본문 추출과 연관성 판단을 거쳐 소스 후보로 채택된다.
@pytest.mark.unit
def test_research_artifact__source_candidate_flow__keeps_linked_ids():
    # Given: connector 수집 결과와 본문 추출 결과를 준비한다.
    source_item = SourceItem(
        source_type="youtube",
        configured_source_id="src-youtube-1",
        item_id="item-1",
        title="AI agent coding workflow",
        url="https://example.com/watch/1",
        raw_summary="AI coding assistant demo",
    )
    article = ExtractedArticle(
        item_id="item-1",
        title="AI agent coding workflow",
        url="https://example.com/watch/1",
        content_text="Autonomous coding assistants can plan and edit code.",
        extracted_at="2026-05-28T10:00:00+09:00",
        language="en",
    )
    keyword_match = KeywordMatch(
        item_id="item-1",
        interest_keyword="AI agent",
        matched_text="AI agent",
        match_type="exact",
    )
    judgment = RelevanceJudgment(
        item_id="item-1",
        is_relevant=True,
        score=0.86,
        threshold=0.7,
        matched_keywords=["AI agent"],
        reason="AI agent coding workflow를 직접 다루므로 관심사와 관련이 높다.",
    )

    # When: threshold를 통과한 글을 소스 후보 artifact로 만든다.
    candidate = SourceCandidate(
        candidate_id="candidate-1",
        item_id=judgment.item_id,
        source_type=source_item.source_type,
        configured_source_id=source_item.configured_source_id,
        title=source_item.title,
        url=source_item.url,
        relevance_score=judgment.score,
        threshold=judgment.threshold,
        matched_keywords=judgment.matched_keywords,
        selected_reason=judgment.reason,
    )

    # Then: 각 artifact는 item_id를 기준으로 같은 원본 항목을 추적할 수 있다.
    assert source_item.item_id == article.item_id
    assert keyword_match.item_id == candidate.item_id
    assert candidate.relevance_score == 0.86
    assert candidate.matched_keywords == ["AI agent"]


# 시나리오 2. 카테고리 체계와 분류 결과는 taxonomy id/version으로 연결된다.
@pytest.mark.unit
def test_research_artifact__category_assignment__references_taxonomy():
    # Given: 사용자 관심사로부터 만든 카테고리 체계를 준비한다.
    category = CategoryDefinition(
        category_id="cat-ai-agent",
        name="AI 에이전트",
        description="자율적으로 작업을 수행하는 AI 도구와 워크플로",
        keywords=["AI agent", "coding assistant"],
    )
    taxonomy = CategoryTaxonomy(
        taxonomy_id="tax-ai-20260528",
        version="v1",
        generated_from_keywords=["AI agent", "LLM"],
        method="llm",
        categories=[category],
    )

    # When: 채택된 소스 후보를 taxonomy 안의 카테고리에 배정한다.
    assignment = CategoryAssignment(
        candidate_id="candidate-1",
        category_id=category.category_id,
        category_name=category.name,
        confidence=0.91,
        reason="코딩 작업을 수행하는 AI agent workflow가 핵심 주제다.",
        taxonomy_id=taxonomy.taxonomy_id,
        taxonomy_version=taxonomy.version,
    )

    # Then: 분류 결과는 어떤 taxonomy 기준으로 배정됐는지 재현할 수 있다.
    assert assignment.category_id == taxonomy.categories[0].category_id
    assert assignment.taxonomy_id == "tax-ai-20260528"
    assert assignment.taxonomy_version == "v1"


# 시나리오 3. 소스 단위 분석 결과는 묶음, 키워드, 트렌드, 리포트 콘텐츠로 연결된다.
@pytest.mark.unit
def test_research_artifact__report_content_flow__links_insights():
    # Given: 채택된 소스 하나에서 뽑은 분석 결과를 준비한다.
    source_insight = SourceInsight(
        source_insight_id="insight-1",
        candidate_id="candidate-1",
        category_id="cat-ai-agent",
        summary="AI coding assistant가 개발 workflow를 자동화하는 흐름을 다룬다.",
        key_points=["agent workflow", "code editing automation"],
        importance_score=0.82,
        why_it_matters="개발 생산성 자동화 흐름을 보여주는 사례다.",
    )

    # When: 여러 분석 artifact가 최종 리포트 콘텐츠의 입력으로 묶인다.
    bundle = InsightBundle(
        bundle_id="bundle-ai-agent",
        bundle_type="category",
        title="AI 에이전트",
        source_insight_ids=[source_insight.source_insight_id],
        summary="AI agent 도구가 개발 workflow를 자동화하는 방향으로 발전하고 있다.",
        key_takeaways=["coding agent 활용 사례가 늘고 있다."],
        category_id="cat-ai-agent",
    )
    keyword = KeywordInsight(
        keyword_insight_id="keyword-1",
        scope="bundle",
        scope_id=bundle.bundle_id,
        keywords=["AI agent", "coding assistant"],
    )
    trend = TrendInsight(
        trend_id="trend-1",
        scope="bundle",
        scope_id=bundle.bundle_id,
        title="코딩 에이전트 자동화 확산",
        summary="여러 소스에서 agent 기반 개발 자동화 사례가 반복 관찰된다.",
        trend_type="emerging",
        source_insight_ids=[source_insight.source_insight_id],
        confidence=0.76,
    )
    report = ReportContent(
        report_id="report-1",
        title="AI 개발 자동화 리포트",
        generated_at="2026-05-28T10:10:00+09:00",
        interest_keywords=["AI agent", "LLM"],
        bundle_ids=[bundle.bundle_id],
        keyword_insight_ids=[keyword.keyword_insight_id],
        trend_insight_ids=[trend.trend_id],
    )

    # Then: ReportContent는 렌더링에 필요한 상위 artifact id를 안정적으로 참조한다.
    assert report.bundle_ids == ["bundle-ai-agent"]
    assert report.keyword_insight_ids == ["keyword-1"]
    assert report.trend_insight_ids == ["trend-1"]


# 시나리오 4. score/confidence 계열 값은 0.0~1.0 범위를 벗어나면 거부된다.
@pytest.mark.unit
def test_research_artifact__invalid_score_bounds__raises_validation_error():
    # Given: relevance score가 허용 범위를 벗어난 판단 payload를 준비한다.
    invalid_payload = {
        "item_id": "item-1",
        "is_relevant": True,
        "score": 1.2,
        "threshold": 0.7,
        "matched_keywords": ["AI agent"],
        "reason": "AI agent를 다루므로 관련성이 높다.",
    }

    # When / Then: Pydantic 검증 단계에서 score 범위 오류를 발생시킨다.
    with pytest.raises(ValidationError) as error:
        RelevanceJudgment(**invalid_payload)

    assert any(err["loc"] == ("score",) for err in error.value.errors())
