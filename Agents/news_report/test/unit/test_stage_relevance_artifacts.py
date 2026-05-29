"""artifact 기반 relevance stage 단위 테스트."""

import pytest
from typing import cast

from contracts.research_artifact import RelevanceJudgment
from providers.protocols import ProviderOptions, StructuredModel
from stages.relevance_artifacts import (
    item_id_for,
    select_source_candidates,
    source_candidate_from_item,
)


class FakeRelevanceProvider:
    """RelevanceJudgment를 반환하는 structured provider fake."""

    def __init__(self, judgments: list[RelevanceJudgment]):
        self._judgments: list[RelevanceJudgment] = judgments
        self.prompts: list[str] = []

    def run(self, prompt: str) -> str:
        return self.generate_text(prompt)

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
        _ = (schema_model, options)
        self.prompts.append(prompt)
        return cast(StructuredModel, self._judgments.pop(0))


class FailingRelevanceProvider:
    """RelevanceJudgment 생성에 실패하는 structured provider fake."""

    def run(self, prompt: str) -> str:
        return self.generate_text(prompt)

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
        raise ValueError("invalid structured output")


# 시나리오 1. 관련성 기준을 통과한 item은 SourceCandidate로 채택된다.
@pytest.mark.unit
def test_select_source_candidates__relevant_item__returns_candidate():
    # Given: provider가 threshold를 통과하는 relevance 판단을 반환하도록 준비한다.
    item = {
        "title": "AI agent 개발 workflow",
        "url": "https://example.com/ai-agent",
        "summary": "AI agent가 개발 자동화를 돕는 사례",
        "contentText": "autonomous coding assistant",
        "sourceType": "google_news",
        "publishedAt": "2026-05-28T10:00:00+09:00",
    }
    provider = FakeRelevanceProvider(
        [
            RelevanceJudgment(
                item_id="model-returned-id",
                is_relevant=True,
                score=0.86,
                threshold=0.1,
                matched_keywords=["AI agent"],
                reason="AI agent 개발 자동화 사례를 직접 다루므로 관련성이 높다.",
            )
        ]
    )
    logs: list[str] = []

    # When: artifact 기반 relevance stage를 실행한다.
    judgments, candidates = select_source_candidates(
        [item],
        ["AI agent"],
        provider,
        logs.append,
        threshold=0.7,
    )

    # Then: 판단 기준값은 pipeline 값으로 고정되고 source candidate가 생성된다.
    expected_item_id = item_id_for(item)
    assert judgments[0].item_id == expected_item_id
    assert judgments[0].threshold == 0.7
    assert candidates[0].item_id == expected_item_id
    assert candidates[0].source_type == "google_news"
    assert candidates[0].selection_rank == 1
    assert candidates[0].relevance_score == 0.86
    assert "item_id:" in provider.prompts[0]
    assert logs == ["  relevance 채택: AI agent 개발 workflow (0.86)"]


# 시나리오 2. threshold를 통과하지 못한 item은 판단만 남기고 후보에서는 제외한다.
@pytest.mark.unit
def test_select_source_candidates__below_threshold__keeps_judgment_only():
    # Given: provider가 낮은 relevance score를 반환하도록 준비한다.
    item = {
        "title": "무관한 일반 뉴스",
        "url": "https://example.com/general",
        "summary": "일반 소식",
        "sourceType": "google_news",
    }
    provider = FakeRelevanceProvider(
        [
            RelevanceJudgment(
                item_id="item-any",
                is_relevant=True,
                score=0.42,
                threshold=0.7,
                matched_keywords=[],
                reason="관심사와 직접 연결되는 핵심 내용이 부족하다.",
            )
        ]
    )
    logs: list[str] = []

    # When: artifact 기반 relevance stage를 실행한다.
    judgments, candidates = select_source_candidates(
        [item],
        ["AI agent"],
        provider,
        logs.append,
        threshold=0.7,
    )

    # Then: relevance 판단은 남지만 분석 대상 후보로는 채택하지 않는다.
    assert len(judgments) == 1
    assert candidates == []
    assert logs == ["  relevance 제외: 무관한 일반 뉴스 (0.42)"]


# 시나리오 3. 지원하지 않는 sourceType은 candidate 생성 단계에서 거부한다.
@pytest.mark.unit
def test_source_candidate_from_item__unsupported_source_type__raises_value_error():
    # Given: SourceType 계약에 없는 sourceType을 가진 item을 준비한다.
    item = {
        "title": "AI 뉴스",
        "url": "https://example.com/ai",
        "sourceType": "unknown_source",
    }
    judgment = RelevanceJudgment(
        item_id="item-1",
        is_relevant=True,
        score=0.9,
        threshold=0.7,
        matched_keywords=["AI"],
        reason="AI 소식을 직접 다루므로 관련성이 높다.",
    )

    # When / Then: SourceCandidate 계약으로 변환할 수 없어 ValueError를 발생시킨다.
    with pytest.raises(ValueError, match="지원하지 않는 sourceType"):
        _ = source_candidate_from_item(item, judgment, selection_rank=1)


# 시나리오 4. relevance 판단 실패는 전체 stage를 중단하지 않고 warning으로 남긴다.
@pytest.mark.unit
def test_select_source_candidates__provider_failure__continues_with_warning():
    # Given: structured output 생성에 실패하는 provider와 source item을 준비한다.
    item = {
        "title": "AI agent 개발 workflow",
        "url": "https://example.com/ai-agent",
        "summary": "AI agent가 개발 자동화를 돕는 사례",
        "sourceType": "google_news",
    }
    logs: list[str] = []
    warnings: list[str] = []

    # When: artifact 기반 relevance stage를 실행한다.
    judgments, candidates = select_source_candidates(
        [item],
        ["AI agent"],
        FailingRelevanceProvider(),
        logs.append,
        threshold=0.7,
        warnings=warnings,
    )

    # Then: 실패한 item은 제외되고 실패 사유는 warning/log에 남는다.
    assert judgments == []
    assert candidates == []
    assert len(warnings) == 1
    assert "relevance 판단 실패" in warnings[0]
    assert "ValueError" in warnings[0]
    assert logs == [f"  {warnings[0]}"]
