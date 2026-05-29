"""수집된 뉴스 항목을 ontology 카테고리에 배정한다."""

from __future__ import annotations

from ontology.models import NewsOntology


def keyword_match(text: str, ontology: NewsOntology) -> str:
    """가장 많은 키워드가 매칭되는 카테고리 라벨을 반환한다. 없으면 "기타"."""
    lowered = (text or "").lower()
    best_label = "기타"
    best_count = 0

    for category in ontology.categories:
        count = sum(
            1
            for keyword in category.keywords
            if keyword.strip() and keyword.lower() in lowered
        )
        if count > best_count:
            best_count = count
            best_label = category.label

    return best_label if best_count > 0 else "기타"
