"""이미 리포트에 실린 URL 을 기억해 다음 실행에서 다시 수집하지 않는다.

같은 기사가 며칠씩 반복 채택되는 문제를 막는다. 실제 코퍼스(130회 실행)에서 채택
1,697건 중 **1,019건(60%)이 이미 봤던 URL** 이었고, 한 기사는 43일에 걸쳐 다시 실렸다.

**기억은 만료하지 않는다.** RSS·유튜브 피드는 새 글이 계속 들어오는 롤링 창이라, 본 것을
걸러도 소스가 마르지 않는다. 안 나오는 날은 소스가 실제로 안 올린 날이다. 용량도 문제가
아니다 — 실행당 고유 URL 이 5건 남짓이라 1년에 2천 건 미만이다.

**기록 기준은 «채택» 이다.** 수집됐지만 관련성에서 떨어진 기사는 남기지 않는다. 나중에
맥락이 생겨 관련성이 올라가면 다시 후보가 되어야 하기 때문이다.
"""

from __future__ import annotations

import json
import os
import tempfile
import urllib.parse
from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field

SCHEMA_VERSION = 1


def canonical_url(url: str) -> str:
    """동일 기사 판별용 URL.

    fragment 만 지우고 경로·query 는 남긴다 — Google News RSS 는 query 에 기사 식별자가
    들어 있어 지우면 서로 다른 기사가 전부 같아진다.
    """
    url = (url or "").strip()
    if not url:
        return ""
    try:
        parts = urllib.parse.urlsplit(url)
        return urllib.parse.urlunsplit(
            (parts.scheme.lower(), parts.netloc.lower(), parts.path, parts.query, "")
        )
    except ValueError:
        return url.split("#", 1)[0]


def seen_urls_path(output_dir: str) -> str:
    return os.path.join(output_dir, "data", "collected", "seen_urls.json")


@dataclass
class SeenUrlStore:
    """URL → 처음 채택된 날짜(ISO). 파일이 없거나 깨졌으면 빈 채로 시작한다."""

    path: str
    entries: dict[str, str] = field(default_factory=dict)

    def __contains__(self, url: str) -> bool:
        return canonical_url(url) in self.entries

    def __len__(self) -> int:
        return len(self.entries)


def load_seen_urls(output_dir: str) -> SeenUrlStore:
    path = seen_urls_path(output_dir)
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
        entries = payload.get("urls") or {}
        if not isinstance(entries, dict):
            entries = {}
    except (OSError, json.JSONDecodeError):
        entries = {}
    return SeenUrlStore(path=path, entries={str(k): str(v) for k, v in entries.items()})


def filter_unseen(
    items: Iterable[Mapping[str, object]],
    store: SeenUrlStore,
) -> tuple[list[Mapping[str, object]], int]:
    """이미 채택했던 URL 을 걸러낸다. `(남은 항목, 걸러낸 수)`.

    URL 이 없는 항목은 판별할 수 없으므로 남긴다 — 뒤쪽 dedupe 가 처리한다.
    """
    kept: list[Mapping[str, object]] = []
    skipped = 0
    for item in items:
        url = str(item.get("url") or "")
        if url and canonical_url(url) in store.entries:
            skipped += 1
            continue
        kept.append(item)
    return kept, skipped


def record_seen(store: SeenUrlStore, urls: Iterable[str], *, today: str) -> int:
    """채택된 URL 을 기록하고 파일에 쓴다. 새로 추가된 수를 돌려준다.

    이미 있는 URL 의 날짜는 덮지 않는다 — «처음 본 날» 이 의미 있는 값이다.
    """
    added = 0
    for url in urls:
        canonical = canonical_url(url)
        if not canonical or canonical in store.entries:
            continue
        store.entries[canonical] = today
        added += 1

    if added:
        _write(store)
    return added


def _write(store: SeenUrlStore) -> None:
    """원자적으로 쓴다. 중간에 죽어도 반쪽 파일이 남으면 안 된다."""
    os.makedirs(os.path.dirname(store.path), exist_ok=True)
    payload = json.dumps(
        {"schemaVersion": SCHEMA_VERSION, "urls": store.entries},
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=os.path.dirname(store.path), delete=False, suffix=".tmp"
    )
    try:
        with handle:
            handle.write(payload + "\n")
        os.replace(handle.name, store.path)
    except BaseException:
        os.unlink(handle.name)
        raise
