"""runner가 호출하는 온톨로지 고수준 서비스."""

from __future__ import annotations

import os
from typing import Any, Iterable

from ontology.builder import build_via_llm, seed_fallback
from ontology.helpers import hash_keywords, normalize_keywords, now_iso
from ontology.models import NewsOntology
from ontology.store import read_cache, write_cache


def load_or_build_for_output_dir(
    interest_keywords: Iterable[str],
    provider: Any,
    output_dir: str,
    log_fn=None,
) -> tuple[NewsOntology, str]:
    """output_dir 기준 ontology 캐시 경로를 준비하고 ontology를 로드/생성한다."""
    ontology_path = os.path.join(output_dir, "data", "ontology", "news_ontology.json")
    legacy_ontology_path = os.path.join(output_dir, "data", "cache", "news_ontology.json")
    migrate_legacy_cache(legacy_ontology_path, ontology_path, log_fn=log_fn)
    return load_or_build(interest_keywords, provider, ontology_path, log_fn=log_fn)


def load_or_build(
    interest_keywords: Iterable[str],
    provider: Any,
    cache_path: str,
    log_fn=None,
) -> tuple[NewsOntology, str]:
    """캐시 적중 시 반환하고, 없으면 LLM 생성 후 실패 시 seed fallback으로 생성한다.

    Returns:
        (ontology, status) where status ∈ {"cached", "regenerated_llm", "regenerated_seed"}.
    """
    log = log_fn or (lambda _message: None)
    normalized = normalize_keywords(interest_keywords)
    target_hash = hash_keywords(normalized)

    cached = read_cache(cache_path)
    if cached is not None and cached.interestKeywordsHash == target_hash and cached.categories:
        return cached, "cached"

    if provider is not None:
        try:
            ontology = build_via_llm(normalized, provider)
            ontology.interestKeywordsHash = target_hash
            ontology.interestKeywords = normalized
            ontology.generatedAt = now_iso()
            ontology.source = "llm"
            write_cache(cache_path, ontology, log)
            return ontology, "regenerated_llm"
        except Exception as error:
            log(f"  ontology LLM 실패 ({type(error).__name__}), seed fallback: {error}")

    ontology = seed_fallback(normalized)
    ontology.interestKeywordsHash = target_hash
    ontology.interestKeywords = normalized
    ontology.generatedAt = now_iso()
    ontology.source = "seed"
    write_cache(cache_path, ontology, log)
    return ontology, "regenerated_seed"


def migrate_legacy_cache(legacy_path: str, target_path: str, log_fn=None) -> None:
    """구 ontology cache 경로에 남은 파일을 새 경로로 1회 이동한다."""
    if not os.path.isfile(legacy_path) or os.path.isfile(target_path):
        return

    log = log_fn or (lambda _message: None)
    try:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        os.replace(legacy_path, target_path)
        log(f"  ontology 파일 이동: {legacy_path} → {target_path}")
    except Exception as error:
        log(f"  ontology 파일 이동 실패: {error}")
