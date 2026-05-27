"""온톨로지 JSON 캐시 파일을 읽고 쓴다."""

from __future__ import annotations

import json
import os

from ontology.models import NewsOntology


def read_cache(path: str) -> NewsOntology | None:
    """캐시 파일을 읽어 NewsOntology로 복원한다. 실패하면 None을 반환한다."""
    if not path or not os.path.isfile(path):
        return None

    try:
        with open(path, "r", encoding="utf-8") as file:
            data = json.load(file)
        return NewsOntology.from_dict(data)
    except Exception:
        return None


def write_cache(path: str, ontology: NewsOntology, log_fn=None) -> None:
    """NewsOntology를 JSON 캐시에 기록한다. 실패는 로그만 남기고 runner를 중단하지 않는다."""
    if not path:
        return

    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            json.dump(ontology.to_dict(), file, ensure_ascii=False, indent=2)
        if log_fn:
            log_fn(f"  ontology cache 저장: {path}")
    except Exception as error:
        if log_fn:
            log_fn(f"  ontology cache 저장 실패: {error}")
