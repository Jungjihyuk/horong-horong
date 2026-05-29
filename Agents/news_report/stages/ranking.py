"""뉴스 item의 중요도 점수를 계산하고 정렬한다."""

from __future__ import annotations


def rank_items(items: list[dict], interest_keywords: list[str], ontology) -> list[dict]:
    """관심 키워드, 카테고리, source 가중치를 기반으로 importanceScore를 계산한다."""
    category_bonus = {category.label: 12 for category in ontology.categories}
    category_bonus["기타"] = 0
    source_weight = {"youtube": 15, "google_news": 10, "yozm_it": 12, "linkedin": 8}

    for item in items:
        text = (
            item.get("title", "")
            + " "
            + item.get("summary", "")
            + " "
            + (item.get("contentText", "") or "")[:2000]
        ).lower()
        relevance = sum(1 for keyword in interest_keywords if keyword.lower() in text)
        category = item.get("category", "기타")
        source = item.get("sourceType", "")
        item["importanceScore"] = min(
            100,
            relevance * 10
            + category_bonus.get(category, 0)
            + source_weight.get(source, 10)
            + 40,
        )

    return sorted(items, key=lambda item: item.get("importanceScore", 0), reverse=True)
