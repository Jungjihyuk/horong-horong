"""수집된 뉴스 item을 runner 내부 표준 형태로 정리한다."""

from __future__ import annotations


def normalize_items(items: list[dict]) -> list[dict]:
    """connector별 원천 item을 공통 필드 형태로 정규화한다."""
    result = []
    for item in items:
        norm = {
            "title": item.get("title", "").strip(),
            "url": item.get("url", ""),
            "publishedAt": item.get("publishedAt", ""),
            "summary": item.get("summary", ""),
            "contentText": item.get("contentText", item.get("summary", "")),
            "sourceType": item.get("sourceType", ""),
            "sourceName": item.get("sourceName", ""),
            "author": item.get("author", ""),
        }
        if norm["title"] and norm["url"]:
            result.append(norm)
    return result


def dedupe_items(items: list[dict]) -> list[dict]:
    """URL 기준으로 중복 item을 제거한다."""
    seen = set()
    result = []
    for item in items:
        url = item.get("url", "")
        if url and url not in seen:
            seen.add(url)
            result.append(item)
    return result
