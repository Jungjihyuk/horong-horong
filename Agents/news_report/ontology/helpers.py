"""온톨로지 공통 유틸리티."""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Iterable


def normalize_keywords(keywords: Iterable[str]) -> list[str]:
    """공백/중복을 정리하되 사용자가 입력한 표기는 보존한다."""
    seen: set[str] = set()
    out: list[str] = []

    for keyword in keywords or []:
        if not keyword:
            continue
        trimmed = str(keyword).strip()
        if not trimmed:
            continue
        key = trimmed.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(trimmed)

    return out


def hash_keywords(keywords: list[str]) -> str:
    """관심 키워드 세트가 바뀌었는지 판단하기 위한 안정적인 해시를 만든다."""
    canonical = "\n".join(sorted(keyword.lower() for keyword in keywords))
    return hashlib.sha1(canonical.encode("utf-8")).hexdigest()


def now_iso() -> str:
    """UTC 기준 ISO 문자열을 반환한다."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
