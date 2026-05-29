"""뉴스 item을 ontology 카테고리에 배정한다."""

from __future__ import annotations

from ontology import keyword_match


def classify_items(items: list[dict], ontology) -> list[dict]:
    """각 item에 `category` 필드를 추가한다."""
    for item in items:
        text = (
            item.get("title", "")
            + " "
            + item.get("summary", "")
            + " "
            + (item.get("contentText", "") or "")[:1000]
        )
        item["category"] = keyword_match(text, ontology)
    return items
