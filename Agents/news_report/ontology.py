"""뉴스 카테고리 동적 온톨로지.

사용자의 관심 키워드 세트를 LLM 으로 *한 번* 클러스터링해 카테고리 사전을 만든다.
이후 매 수집은 그 사전을 기반으로 *키워드 매칭* 으로 빠르게 분류한다.

캐시는 `<outputDir>/data/cache/news_ontology.json` 에 저장된다.
관심 키워드 세트가 변하면(정규화된 해시 비교) 다음 수집 시 자동으로 재생성된다.
LLM 호출이 실패하면 기존 5개 카테고리를 seed 로 사용하면서 관심 키워드를 추가 카테고리로 보존한다.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterable


# 백지 정책 — 기본 하드코딩 카테고리는 두지 않는다. seed fallback 은 *사용자 키워드만* 단독 카테고리화한다.


@dataclass
class NewsCategory:
    label: str
    keywords: list[str]
    description: str = ""


@dataclass
class NewsOntology:
    version: int = 1
    interestKeywordsHash: str = ""
    interestKeywords: list[str] = field(default_factory=list)
    generatedAt: str = ""
    source: str = "seed"  # "llm" | "seed"
    categories: list[NewsCategory] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        return data

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "NewsOntology":
        cats = [NewsCategory(**c) for c in data.get("categories", [])]
        return cls(
            version=int(data.get("version", 1)),
            interestKeywordsHash=str(data.get("interestKeywordsHash", "")),
            interestKeywords=list(data.get("interestKeywords", [])),
            generatedAt=str(data.get("generatedAt", "")),
            source=str(data.get("source", "seed")),
            categories=cats,
        )

    def labels(self) -> list[str]:
        return [c.label for c in self.categories]


# MARK: - Public API

def load_or_build(
    interest_keywords: Iterable[str],
    provider: Any,
    cache_path: str,
    log_fn=None,
) -> tuple[NewsOntology, str]:
    """캐시 적중 시 그대로 반환, 아니면 LLM 으로 빌드, 실패 시 seed fallback.

    Returns:
        (ontology, status) where status ∈ {"cached", "regenerated_llm", "regenerated_seed"}.
    """
    log = log_fn or (lambda _msg: None)
    normalized = _normalize_keywords(interest_keywords)
    target_hash = _hash_keywords(normalized)

    cached = _read_cache(cache_path)
    if cached is not None and cached.interestKeywordsHash == target_hash and cached.categories:
        return cached, "cached"

    # LLM 시도
    if provider is not None:
        try:
            ontology = _build_via_llm(normalized, provider)
            ontology.interestKeywordsHash = target_hash
            ontology.interestKeywords = normalized
            ontology.generatedAt = _now_iso()
            ontology.source = "llm"
            _write_cache(cache_path, ontology, log)
            return ontology, "regenerated_llm"
        except Exception as e:
            log(f"  ontology LLM 실패 ({type(e).__name__}), seed fallback: {e}")

    # Fallback — 가시성·디버깅을 위해 seed 도 캐시 파일에 기록한다.
    # 사용자가 캐시 파일을 직접 삭제하면 다음 실행에서 LLM 재시도.
    ontology = _seed_fallback(normalized)
    ontology.interestKeywordsHash = target_hash
    ontology.interestKeywords = normalized
    ontology.generatedAt = _now_iso()
    ontology.source = "seed"
    _write_cache(cache_path, ontology, log)
    return ontology, "regenerated_seed"


def keyword_match(text: str, ontology: NewsOntology) -> str:
    """주어진 텍스트에서 가장 많은 키워드가 매칭되는 카테고리 라벨 반환. 0개면 "기타"."""
    lowered = (text or "").lower()
    best_label = "기타"
    best_count = 0
    for cat in ontology.categories:
        count = sum(1 for kw in cat.keywords if kw.strip() and kw.lower() in lowered)
        if count > best_count:
            best_count = count
            best_label = cat.label
    return best_label if best_count > 0 else "기타"


# MARK: - LLM

_LLM_PROMPT = """다음은 사용자의 관심 키워드입니다.
이 키워드들을 의미가 유사한 것끼리 **3~7개 카테고리** 로 묶고,
각 카테고리에 대해 다음 정보를 JSON 으로 반환하세요.

- "label": 한국어 카테고리 이름 (10자 이내, 슬래시 가능 예: "AI/반도체")
- "keywords": 그 카테고리에 속하는 사용자 관심 키워드들 + 분류 정확도를 위한 *동의어·관련 영문 표현* (총 5~15개, 영문 표기 포함 권장)
- "description": 1줄 분류 기준

응답은 다음 JSON 만 정확히 출력하세요 (코드 펜스 가능, 다른 텍스트 금지):

{{
  "categories": [
    {{"label": "...", "keywords": ["..."], "description": "..."}}
  ]
}}

사용자 관심 키워드:
{keywords_list}
"""


def _build_via_llm(keywords: list[str], provider: Any) -> NewsOntology:
    if not keywords:
        raise ValueError("관심 키워드가 비어 있어 LLM 클러스터링 생략")
    prompt = _LLM_PROMPT.format(keywords_list="\n".join(f"- {k}" for k in keywords))
    raw = provider.run(prompt)
    payload = _parse_llm_json(raw)
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


_JSON_FENCE_RE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.DOTALL)


def _parse_llm_json(raw: str) -> dict[str, Any]:
    """코드 펜스 / 텍스트 사이에 끼어든 JSON 모두 견고하게 파싱."""
    if not raw:
        raise ValueError("LLM 응답이 비어있음")
    # 1) 코드 펜스 우선
    m = _JSON_FENCE_RE.search(raw)
    if m:
        return json.loads(m.group(1))
    # 2) 일반 JSON 객체 (가장 바깥 중괄호)
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if m:
        return json.loads(m.group(0))
    raise ValueError("LLM 응답에서 JSON 블록을 찾지 못함")


# MARK: - Seed fallback

def _seed_fallback(keywords: list[str]) -> NewsOntology:
    """LLM 호출 불가/실패 시 사용. 백지 정책 — 사용자 키워드 각각을 단독 카테고리로 변환.

    키워드도 없으면 빈 ontology 를 반환 (모든 기사가 "기타" 로 분류됨).
    """
    categories: list[NewsCategory] = [
        NewsCategory(label=kw, keywords=[kw], description="사용자 관심 키워드")
        for kw in keywords
    ]
    return NewsOntology(categories=categories)


# MARK: - Helpers

def _normalize_keywords(keywords: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for kw in keywords or []:
        if not kw:
            continue
        trimmed = str(kw).strip()
        if not trimmed:
            continue
        key = trimmed.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(trimmed)
    return out


def _hash_keywords(keywords: list[str]) -> str:
    canonical = "\n".join(sorted(k.lower() for k in keywords))
    return hashlib.sha1(canonical.encode("utf-8")).hexdigest()


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _read_cache(path: str) -> NewsOntology | None:
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return NewsOntology.from_dict(data)
    except Exception:
        return None


def _write_cache(path: str, ontology: NewsOntology, log_fn=None) -> None:
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(ontology.to_dict(), f, ensure_ascii=False, indent=2)
        if log_fn:
            log_fn(f"  ontology cache 저장: {path}")
    except Exception as e:
        if log_fn:
            log_fn(f"  ontology cache 저장 실패: {e}")
