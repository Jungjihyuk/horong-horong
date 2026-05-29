"""research pattern 계약 단위 테스트."""

import pytest
from typing import cast

from contracts.research_artifact import RelevanceJudgment, SourceInsight, TrendInsight
from ontology import NewsCategory, NewsOntology
from patterns.research import (
    ResearchContext,
    create_research_pattern,
    default_research_pattern_name,
)
from patterns.research.result import ResearchResult
from providers.protocols import ProviderOptions, StructuredModel
from tracing.events import TraceEventName


class FakeStructuredProvider:
    """research pattern context에 전달할 structured provider fake."""

    def __init__(self, judgment: RelevanceJudgment | None = None):
        self._judgment: RelevanceJudgment | None = judgment

    def run(self, prompt: str) -> str:
        return prompt

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        _ = options
        return prompt

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        _ = (prompt, schema_model, options)
        if self._judgment is None:
            raise AssertionError("fake provider judgment is not configured")
        return cast(StructuredModel, self._judgment)


class FakeTrace:
    """TraceWriter 대신 호출 내용을 메모리에 기록하는 fake."""

    def __init__(self):
        self.events: list[tuple[TraceEventName, dict[str, object]]] = []

    def write(self, event: TraceEventName, **kwargs: object) -> object:
        self.events.append((event, kwargs))
        return None


class QueueStructuredProvider:
    """schema 순서대로 준비된 Pydantic 응답을 반환하는 fake."""

    def __init__(self, responses: list[object]):
        self._responses: list[object] = responses

    def run(self, prompt: str) -> str:
        return prompt

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        _ = options
        return prompt

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        _ = (prompt, schema_model, options)
        response = self._responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return cast(StructuredModel, response)


# 시나리오 1. 기본 research pattern 이름으로 evidence synthesis 구현체를 생성한다.
@pytest.mark.unit
def test_research_registry__default_pattern_name__returns_evidence_synthesis():
    # Given: deep research가 사용할 기본 research pattern 이름을 준비한다.
    pattern_name = default_research_pattern_name()

    # When: registry가 research pattern 이름을 구현체로 변환한다.
    pattern = create_research_pattern(pattern_name)

    # Then: evidence synthesis research pattern 계약을 만족하는 구현체가 반환된다.
    assert pattern.name == "evidence_synthesis_v1"
    assert pattern.version == "0.1.0"
    assert callable(pattern.run)


# 시나리오 2. 등록되지 않은 research pattern 이름은 명확한 오류로 거부한다.
@pytest.mark.unit
def test_research_registry__unsupported_pattern_name__raises_value_error():
    # Given: registry에 등록되지 않은 research pattern 이름을 준비한다.
    pattern_name = "unknown_research_pattern"

    # When / Then: research pattern 생성 단계에서 ValueError를 발생시킨다.
    with pytest.raises(ValueError, match="지원하지 않는 research pattern"):
        _ = create_research_pattern(pattern_name)


# 시나리오 3. skeleton evidence synthesis pattern은 빈 artifact 묶음을 반환한다.
@pytest.mark.unit
def test_evidence_synthesis__empty_items__returns_empty_research_result():
    # Given: 아직 분석 대상 item이 없는 research context를 준비한다.
    logs: list[str] = []
    context = ResearchContext(
        items=[],
        interest_keywords=["AI agent"],
        provider=FakeStructuredProvider(),
        log=logs.append,
    )
    pattern = create_research_pattern(default_research_pattern_name())

    # When: evidence synthesis research pattern을 실행한다.
    result = pattern.run(context)

    # Then: 이후 stage가 채워 넣을 수 있는 빈 artifact 묶음이 반환된다.
    assert isinstance(result, ResearchResult)
    assert result.relevance_judgments == []
    assert result.source_candidates == []
    assert result.report_content is None
    assert logs == ["Research pattern evidence_synthesis_v1: 0 items prepared"]


# 시나리오 4. evidence synthesis pattern은 관련 item을 source candidate로 만든다.
@pytest.mark.unit
def test_evidence_synthesis__relevant_item__returns_source_candidate():
    # Given: relevance 판단을 통과할 수 있는 item과 provider fake를 준비한다.
    judgment = RelevanceJudgment(
        item_id="item-from-model",
        is_relevant=True,
        score=0.91,
        threshold=0.7,
        matched_keywords=["AI agent"],
        reason="AI agent 개발 자동화 사례를 직접 다루므로 관련성이 높다.",
    )
    context = ResearchContext(
        items=[
            {
                "title": "AI agent 개발 workflow",
                "url": "https://example.com/ai-agent",
                "summary": "AI agent가 개발 자동화를 돕는 사례",
                "sourceType": "google_news",
            }
        ],
        interest_keywords=["AI agent"],
        provider=FakeStructuredProvider(judgment),
        log=lambda message: None,
    )
    pattern = create_research_pattern(default_research_pattern_name())

    # When: evidence synthesis research pattern을 실행한다.
    result = pattern.run(context)

    # Then: RelevanceJudgment와 SourceCandidate artifact가 함께 반환된다.
    assert len(result.relevance_judgments) == 1
    assert len(result.source_candidates) == 1
    assert result.source_candidates[0].title == "AI agent 개발 workflow"
    assert result.source_candidates[0].relevance_score == 0.91


# 시나리오 5. ontology가 있으면 모든 research artifact 묶음을 채운다.
@pytest.mark.unit
def test_evidence_synthesis__with_ontology__returns_full_artifacts():
    # Given: relevance, source insight, trend insight 응답을 순서대로 반환하는 provider를 준비한다.
    provider = QueueStructuredProvider(
        [
            RelevanceJudgment(
                item_id="item-from-model",
                is_relevant=True,
                score=0.91,
                threshold=0.7,
                matched_keywords=["AI agent"],
                reason="AI agent 개발 자동화 사례를 직접 다루므로 관련성이 높다.",
            ),
            SourceInsight(
                source_insight_id="model-source-insight",
                candidate_id="model-candidate",
                category_id=None,
                summary="AI agent가 개발 workflow 자동화를 돕는 사례다.",
                key_points=["코드 작성 자동화", "개발 생산성 개선"],
                importance_score=0.84,
                why_it_matters="개발 자동화 흐름을 이해하는 데 중요하다.",
            ),
            TrendInsight(
                trend_id="model-trend",
                scope="bundle",
                scope_id="model-bundle",
                title="AI agent 개발 자동화 확산",
                summary="AI agent가 개발 workflow 자동화 도구로 확산되고 있다.",
                trend_type="emerging",
                source_insight_ids=[],
                confidence=0.73,
            ),
        ]
    )
    ontology = NewsOntology(
        version=1,
        interestKeywordsHash="ai",
        interestKeywords=["AI agent"],
        categories=[
            NewsCategory(
                label="AI 에이전트",
                keywords=["AI agent", "개발"],
                description="AI agent 개발 자동화",
            )
        ],
    )
    context = ResearchContext(
        items=[
            {
                "title": "AI agent 개발 workflow",
                "url": "https://example.com/ai-agent",
                "summary": "AI agent가 개발 자동화를 돕는 사례",
                "contentText": "AI agent 개발 자동화",
                "sourceType": "google_news",
            }
        ],
        interest_keywords=["AI agent"],
        provider=provider,
        log=lambda message: None,
        ontology=ontology,
    )
    pattern = create_research_pattern(default_research_pattern_name())

    # When: evidence synthesis research pattern을 실행한다.
    result = pattern.run(context)

    # Then: research_artifact.py의 주요 artifact들이 모두 연결되어 반환된다.
    assert len(result.source_items) == 1
    assert len(result.extracted_articles) == 1
    assert len(result.keyword_matches) == 1
    assert len(result.relevance_judgments) == 1
    assert len(result.source_candidates) == 1
    assert result.category_taxonomy is not None
    assert len(result.category_assignments) == 1
    assert len(result.source_insights) == 1
    assert len(result.insight_bundles) == 1
    assert len(result.keyword_insights) >= 1
    assert len(result.trend_insights) == 1
    assert result.report_content is not None


# 시나리오 6. evidence synthesis pattern은 시작/완료 trace를 남긴다.
@pytest.mark.unit
def test_evidence_synthesis__trace_enabled__writes_stage_started_event():
    # Given: trace writer fake가 포함된 research context를 준비한다.
    trace = FakeTrace()
    context = ResearchContext(
        items=[
            {
                "id": "item-1",
                "title": "AI agent news",
                "url": "https://example.com/ai-agent-news",
                "sourceType": "google_news",
            }
        ],
        interest_keywords=["AI agent"],
        provider=FakeStructuredProvider(
            RelevanceJudgment(
                item_id="item-from-model",
                is_relevant=True,
                score=0.88,
                threshold=0.7,
                matched_keywords=["AI agent"],
                reason="AI agent news가 관심사와 직접 연결되어 관련성이 높다.",
            )
        ),
        log=lambda message: None,
        trace=trace,
    )
    pattern = create_research_pattern(default_research_pattern_name())

    # When: evidence synthesis research pattern을 실행한다.
    _ = pattern.run(context)

    # Then: trace에는 research stage 시작/완료 이벤트와 pattern 메타데이터가 기록된다.
    assert trace.events == [
        (
            "stage_started",
            {
                "stage": "research",
                "payload": {
                    "pattern": "evidence_synthesis_v1",
                    "version": "0.1.0",
                    "item_count": 1,
                    "interest_keywords": ["AI agent"],
                },
            },
        ),
        (
            "stage_completed",
            {
                "stage": "research",
                "payload": {
                    "pattern": "evidence_synthesis_v1",
                    "version": "0.1.0",
                    "source_item_count": 1,
                    "extracted_article_count": 1,
                    "keyword_match_count": 1,
                    "relevance_judgment_count": 1,
                    "source_candidate_count": 1,
                    "source_insight_count": 0,
                    "insight_bundle_count": 0,
                    "trend_insight_count": 0,
                    "warning_count": 0,
                },
            },
        ),
    ]


# 시나리오 7. source insight 생성 실패는 candidate를 유지하고 warning으로 낮춘다.
@pytest.mark.unit
def test_evidence_synthesis__source_insight_failure__keeps_candidate_with_warning():
    # Given: relevance 판단은 성공하지만 SourceInsight 생성은 실패하는 provider를 준비한다.
    provider = QueueStructuredProvider(
        [
            RelevanceJudgment(
                item_id="item-from-model",
                is_relevant=True,
                score=0.91,
                threshold=0.7,
                matched_keywords=["AI agent"],
                reason="AI agent 개발 자동화 사례를 직접 다루므로 관련성이 높다.",
            ),
            ValueError("invalid source insight json"),
        ]
    )
    ontology = NewsOntology(
        version=1,
        interestKeywordsHash="ai",
        interestKeywords=["AI agent"],
        categories=[
            NewsCategory(
                label="AI 에이전트",
                keywords=["AI agent", "개발"],
                description="AI agent 개발 자동화",
            )
        ],
    )
    context = ResearchContext(
        items=[
            {
                "title": "AI agent 개발 workflow",
                "url": "https://example.com/ai-agent",
                "summary": "AI agent가 개발 자동화를 돕는 사례",
                "contentText": "AI agent 개발 자동화",
                "sourceType": "google_news",
            }
        ],
        interest_keywords=["AI agent"],
        provider=provider,
        log=lambda message: None,
        ontology=ontology,
    )
    pattern = create_research_pattern(default_research_pattern_name())

    # When: evidence synthesis research pattern을 실행한다.
    result = pattern.run(context)

    # Then: candidate와 category assignment는 유지하고 insight 누락은 warning에 남긴다.
    assert len(result.source_candidates) == 1
    assert len(result.category_assignments) == 1
    assert result.source_insights == []
    assert result.insight_bundles == []
    assert result.trend_insights == []
    assert result.report_content is not None
    assert len(result.warnings) == 1
    assert "source insight 생성 실패" in result.warnings[0]


# 시나리오 8. trend insight 생성 실패는 bundle을 유지하고 warning으로 낮춘다.
@pytest.mark.unit
def test_evidence_synthesis__trend_insight_failure__keeps_bundle_with_warning():
    # Given: source insight까지는 성공하지만 TrendInsight 생성은 실패하는 provider를 준비한다.
    provider = QueueStructuredProvider(
        [
            RelevanceJudgment(
                item_id="item-from-model",
                is_relevant=True,
                score=0.91,
                threshold=0.7,
                matched_keywords=["AI agent"],
                reason="AI agent 개발 자동화 사례를 직접 다루므로 관련성이 높다.",
            ),
            SourceInsight(
                source_insight_id="model-source-insight",
                candidate_id="model-candidate",
                category_id=None,
                summary="AI agent가 개발 workflow 자동화를 돕는 사례다.",
                key_points=["코드 작성 자동화", "개발 생산성 개선"],
                importance_score=0.84,
                why_it_matters="개발 자동화 흐름을 이해하는 데 중요하다.",
            ),
            ValueError("invalid trend insight json"),
        ]
    )
    ontology = NewsOntology(
        version=1,
        interestKeywordsHash="ai",
        interestKeywords=["AI agent"],
        categories=[
            NewsCategory(
                label="AI 에이전트",
                keywords=["AI agent", "개발"],
                description="AI agent 개발 자동화",
            )
        ],
    )
    context = ResearchContext(
        items=[
            {
                "title": "AI agent 개발 workflow",
                "url": "https://example.com/ai-agent",
                "summary": "AI agent가 개발 자동화를 돕는 사례",
                "contentText": "AI agent 개발 자동화",
                "sourceType": "google_news",
            }
        ],
        interest_keywords=["AI agent"],
        provider=provider,
        log=lambda message: None,
        ontology=ontology,
    )
    pattern = create_research_pattern(default_research_pattern_name())

    # When: evidence synthesis research pattern을 실행한다.
    result = pattern.run(context)

    # Then: source insight와 bundle은 유지하고 trend 누락은 warning에 남긴다.
    assert len(result.source_insights) == 1
    assert len(result.insight_bundles) == 1
    assert result.trend_insights == []
    assert result.report_content is not None
    assert len(result.warnings) == 1
    assert "trend insight 생성 실패" in result.warnings[0]
