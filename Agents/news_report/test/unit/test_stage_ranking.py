"""뉴스 item ranking stage 단위 테스트."""

import pytest

from ontology import NewsCategory, NewsOntology
from stages.ranking import rank_items


# 시나리오 1. 관심 키워드와 source/category 가중치로 중요도 점수를 계산한다.
@pytest.mark.unit
def test_rank_items__keyword_and_source_match__sorts_by_importance_score():
    # Given: 같은 카테고리 안에서 관심 키워드 일치 수가 다른 item을 준비한다.
    ontology = NewsOntology(
        categories=[NewsCategory(label="AI", keywords=["AI"], description="")]
    )
    items = [
        {
            "title": "일반 개발 뉴스",
            "summary": "",
            "contentText": "",
            "category": "기타",
            "sourceType": "google_news",
        },
        {
            "title": "AI agent 개발",
            "summary": "AI 자동화",
            "contentText": "",
            "category": "AI",
            "sourceType": "youtube",
        },
    ]

    # When: ranking stage를 실행한다.
    ranked = rank_items(items, ["AI", "자동화"], ontology)

    # Then: 관심 키워드와 가중치가 높은 item이 먼저 온다.
    assert ranked[0]["title"] == "AI agent 개발"
    assert ranked[0]["importanceScore"] > ranked[1]["importanceScore"]
