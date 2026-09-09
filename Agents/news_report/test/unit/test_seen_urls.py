"""이미 채택한 URL 기억 단위 테스트.

실측(130회 실행)에서 채택 1,697건 중 1,019건(60%)이 재수집분이었다. 한 기사는 43일에
걸쳐 다시 실렸다. 이 필터가 없으면 같은 기사에 LLM 비용을 반복해서 쓴다.
"""

import json

import pytest

from storage.seen_urls import (
    canonical_url,
    filter_unseen,
    load_seen_urls,
    record_seen,
    seen_urls_path,
)


# 시나리오 1. Google News 는 query 에 기사 식별자가 있어 지우면 안 된다.
@pytest.mark.unit
def test_canonical_url__query_preserved_fragment_dropped():
    first = "https://news.google.com/rss/articles/CBMiAAA?oc=5#top"
    second = "https://news.google.com/rss/articles/CBMiBBB?oc=5"

    assert canonical_url(first) == "https://news.google.com/rss/articles/CBMiAAA?oc=5"
    assert canonical_url(first) != canonical_url(second)


@pytest.mark.unit
def test_canonical_url__host_case_and_blank():
    assert canonical_url("HTTPS://News.Google.COM/a") == "https://news.google.com/a"
    assert canonical_url("") == ""
    assert canonical_url(None) == ""


# 시나리오 2. 없던 파일이면 빈 채로 시작한다.
@pytest.mark.unit
def test_load_seen_urls__missing_file__starts_empty(tmp_path):
    store = load_seen_urls(str(tmp_path))

    assert len(store) == 0
    assert store.path == seen_urls_path(str(tmp_path))


@pytest.mark.unit
def test_load_seen_urls__corrupt_file__starts_empty(tmp_path):
    path = tmp_path / "data" / "collected" / "seen_urls.json"
    path.parent.mkdir(parents=True)
    path.write_text("{ 깨진 JSON", encoding="utf-8")

    assert len(load_seen_urls(str(tmp_path))) == 0


# 시나리오 3. 이미 채택한 URL 은 걸러내고, URL 이 없는 항목은 남긴다.
@pytest.mark.unit
def test_filter_unseen__skips_known_keeps_unknown_and_urlless(tmp_path):
    store = load_seen_urls(str(tmp_path))
    record_seen(store, ["https://a.test/1"], today="2026-09-01")

    items = [
        {"title": "이미 본 것", "url": "https://a.test/1"},
        {"title": "fragment 만 다른 같은 것", "url": "https://a.test/1#section"},
        {"title": "새 것", "url": "https://a.test/2"},
        {"title": "URL 이 없는 것"},
    ]

    kept, skipped = filter_unseen(items, store)

    assert skipped == 2
    assert [item["title"] for item in kept] == ["새 것", "URL 이 없는 것"]


# 시나리오 4. 처음 본 날짜는 덮어쓰지 않는다.
@pytest.mark.unit
def test_record_seen__does_not_overwrite_first_seen_date(tmp_path):
    store = load_seen_urls(str(tmp_path))
    record_seen(store, ["https://a.test/1"], today="2026-09-01")

    added = record_seen(store, ["https://a.test/1", "https://a.test/2"], today="2026-09-09")

    assert added == 1, "이미 아는 URL 은 새로 추가되지 않는다"
    assert store.entries[canonical_url("https://a.test/1")] == "2026-09-01"
    assert store.entries[canonical_url("https://a.test/2")] == "2026-09-09"


# 시나리오 5. 다음 실행이 파일에서 그대로 이어받는다.
@pytest.mark.unit
def test_record_seen__persists_across_loads(tmp_path):
    first = load_seen_urls(str(tmp_path))
    record_seen(first, ["https://a.test/1", "https://a.test/2"], today="2026-09-01")

    second = load_seen_urls(str(tmp_path))

    assert len(second) == 2
    assert "https://a.test/1" in second

    payload = json.loads((tmp_path / "data" / "collected" / "seen_urls.json").read_text(encoding="utf-8"))
    assert payload["schemaVersion"] == 1


# 시나리오 6. 기억은 만료하지 않는다 — 오래된 항목도 계속 걸러진다.
@pytest.mark.unit
def test_filter_unseen__old_entries_still_filter(tmp_path):
    store = load_seen_urls(str(tmp_path))
    record_seen(store, ["https://a.test/old"], today="2026-01-01")

    kept, skipped = filter_unseen([{"url": "https://a.test/old"}], store)

    assert skipped == 1
    assert kept == []
