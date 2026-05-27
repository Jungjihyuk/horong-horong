"""뉴스 ontology 패키지 단위 테스트."""

from __future__ import annotations

import json

import pytest

from ontology import NewsCategory, NewsOntology, keyword_match, load_or_build
from ontology.helpers import hash_keywords


class FakeProvider:
    def __init__(self, response: str | None = None, error: Exception | None = None):
        self.response = response
        self.error = error
        self.prompts: list[str] = []

    def run(self, prompt: str) -> str:
        self.prompts.append(prompt)
        if self.error:
            raise self.error
        return self.response or ""


# 시나리오 1. 관심 키워드 해시가 같은 캐시가 있으면 LLM을 호출하지 않고 재사용한다.
@pytest.mark.unit
def test_load_or_build__matching_cache__returns_cached_ontology(tmp_path):
    # Given: 현재 관심 키워드와 해시가 일치하는 ontology 캐시를 준비한다.
    keywords = ["AI", "Swift"]
    cache_path = tmp_path / "news_ontology.json"
    cached = NewsOntology(
        interestKeywordsHash=hash_keywords(keywords),
        interestKeywords=keywords,
        source="llm",
        categories=[
            NewsCategory(label="AI", keywords=["AI"], description="인공지능"),
        ],
    )
    cache_path.write_text(
        json.dumps(cached.to_dict(), ensure_ascii=False),
        encoding="utf-8",
    )
    provider = FakeProvider(error=AssertionError("cache hit should not call provider"))

    # When: ontology를 load_or_build로 읽는다.
    ontology, status = load_or_build(keywords, provider, str(cache_path))

    # Then: 캐시된 ontology가 그대로 반환된다.
    assert status == "cached"
    assert ontology.labels() == ["AI"]
    assert provider.prompts == []


# 시나리오 2. 캐시가 없고 LLM이 정상 응답하면 ontology를 생성하고 캐시에 저장한다.
@pytest.mark.unit
def test_load_or_build__valid_provider_response__writes_llm_cache(tmp_path):
    # Given: 카테고리 JSON을 반환하는 provider와 빈 캐시 경로를 준비한다.
    cache_path = tmp_path / "news_ontology.json"
    provider = FakeProvider(
        response=json.dumps(
            {
                "categories": [
                    {
                        "label": "AI/개발",
                        "keywords": ["AI", "Swift", "agent"],
                        "description": "AI 개발 도구",
                    }
                ]
            },
            ensure_ascii=False,
        )
    )

    # When: ontology를 새로 생성한다.
    ontology, status = load_or_build(["AI", "Swift"], provider, str(cache_path))

    # Then: LLM 기반 ontology가 반환되고 캐시 파일에도 같은 source가 기록된다.
    assert status == "regenerated_llm"
    assert ontology.source == "llm"
    assert ontology.labels() == ["AI/개발"]

    cached = json.loads(cache_path.read_text(encoding="utf-8"))
    assert cached["source"] == "llm"
    assert cached["categories"][0]["label"] == "AI/개발"


# 시나리오 3. LLM 생성이 실패하면 사용자 키워드 기반 seed ontology로 대체한다.
@pytest.mark.unit
def test_load_or_build__provider_failure__uses_seed_fallback(tmp_path):
    # Given: 실패하는 provider와 중복/공백이 섞인 관심 키워드를 준비한다.
    cache_path = tmp_path / "news_ontology.json"
    logs: list[str] = []
    provider = FakeProvider(error=RuntimeError("boom"))

    # When: ontology 생성을 시도한다.
    ontology, status = load_or_build(
        [" AI ", "ai", "Swift"],
        provider,
        str(cache_path),
        log_fn=logs.append,
    )

    # Then: 정규화된 사용자 키워드가 각각 seed 카테고리로 남는다.
    assert status == "regenerated_seed"
    assert ontology.source == "seed"
    assert ontology.labels() == ["AI", "Swift"]
    assert any("ontology LLM 실패" in message for message in logs)


# 시나리오 4. keyword_match는 본문과 가장 많이 일치한 카테고리를 반환한다.
@pytest.mark.unit
def test_keyword_match__matching_keywords__returns_best_category():
    # Given: 서로 다른 키워드를 가진 ontology와 뉴스 본문을 준비한다.
    ontology = NewsOntology(
        categories=[
            NewsCategory(label="AI", keywords=["AI", "agent"]),
            NewsCategory(label="Swift", keywords=["Swift"]),
        ]
    )
    text = "새로운 AI agent 개발 흐름"

    # When: 본문을 ontology 기준으로 분류한다.
    category = keyword_match(text, ontology)

    # Then: 가장 많은 키워드가 일치한 카테고리가 선택된다.
    assert category == "AI"
