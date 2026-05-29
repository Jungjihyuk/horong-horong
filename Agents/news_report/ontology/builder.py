"""LLM 또는 seed 기반으로 뉴스 온톨로지를 생성한다."""

from __future__ import annotations

import json
import re
from typing import Any

from ontology.models import NewsCategory, NewsOntology
from ontology.prompts import LLM_PROMPT


def build_via_llm(keywords: list[str], provider: Any) -> NewsOntology:
    """관심 키워드를 LLM으로 클러스터링해 ontology 초안을 만든다."""
    if not keywords:
        raise ValueError("관심 키워드가 비어 있어 LLM 클러스터링 생략")

    prompt = LLM_PROMPT.format(keywords_list="\n".join(f"- {k}" for k in keywords))
    raw = provider.run(prompt)
    payload = parse_llm_json(raw)
    cats_data = payload.get("categories") or []
    if not isinstance(cats_data, list) or not cats_data:
        raise ValueError("LLM 응답에 categories 배열이 없거나 비어있음")

    categories: list[NewsCategory] = []
    for entry in cats_data:
        if not isinstance(entry, dict):
            continue
        label = str(entry.get("label", "")).strip()
        kws_raw = entry.get("keywords") or []
        if not label or not isinstance(kws_raw, list):
            continue
        kws = [str(k).strip() for k in kws_raw if str(k).strip()]
        if not kws:
            continue
        description = str(entry.get("description", "")).strip()
        categories.append(NewsCategory(label=label, keywords=kws, description=description))

    if not categories:
        raise ValueError("LLM 응답에서 유효한 카테고리를 하나도 추출하지 못함")
    return NewsOntology(categories=categories)


def seed_fallback(keywords: list[str]) -> NewsOntology:
    """LLM 호출 불가/실패 시 사용자 키워드 각각을 단독 카테고리로 변환한다."""
    categories: list[NewsCategory] = [
        NewsCategory(label=kw, keywords=[kw], description="사용자 관심 키워드")
        for kw in keywords
    ]
    return NewsOntology(categories=categories)


_JSON_FENCE_RE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.DOTALL)


def parse_llm_json(raw: str) -> dict[str, Any]:
    """코드 펜스 또는 일반 텍스트 사이의 JSON 객체를 파싱한다."""
    if not raw:
        raise ValueError("LLM 응답이 비어있음")

    fence_match = _JSON_FENCE_RE.search(raw)
    if fence_match:
        return json.loads(fence_match.group(1))

    object_match = re.search(r"\{.*\}", raw, re.DOTALL)
    if object_match:
        return json.loads(object_match.group(0))

    raise ValueError("LLM 응답에서 JSON 블록을 찾지 못함")
