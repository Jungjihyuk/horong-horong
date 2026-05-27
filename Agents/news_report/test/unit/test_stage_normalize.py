"""뉴스 item normalize stage 단위 테스트."""

import pytest

from stages.normalize import dedupe_items, normalize_items


# 시나리오 1. connector 원천 item을 runner 내부 공통 필드로 정규화한다.
@pytest.mark.unit
def test_normalize_items__valid_items__returns_standard_fields():
    # Given: title/url이 있는 원천 item과 title이 비어 있는 item을 준비한다.
    items = [
        {
            "title": "  AI 뉴스  ",
            "url": "https://example.com/1",
            "summary": "요약",
            "sourceType": "google_news",
        },
        {"title": "", "url": "https://example.com/2"},
    ]

    # When: normalize stage를 실행한다.
    normalized = normalize_items(items)

    # Then: 필수값이 있는 item만 공통 필드 형태로 남는다.
    assert normalized == [
        {
            "title": "AI 뉴스",
            "url": "https://example.com/1",
            "publishedAt": "",
            "summary": "요약",
            "contentText": "요약",
            "sourceType": "google_news",
            "sourceName": "",
            "author": "",
        }
    ]


# 시나리오 2. 같은 URL의 item은 첫 번째 항목만 유지한다.
@pytest.mark.unit
def test_dedupe_items__duplicate_urls__keeps_first_item():
    # Given: URL이 중복된 item 목록을 준비한다.
    items = [
        {"title": "첫 번째", "url": "https://example.com/1"},
        {"title": "두 번째", "url": "https://example.com/1"},
        {"title": "세 번째", "url": "https://example.com/2"},
    ]

    # When: dedupe stage를 실행한다.
    deduped = dedupe_items(items)

    # Then: 같은 URL은 처음 등장한 item만 남는다.
    assert deduped == [
        {"title": "첫 번째", "url": "https://example.com/1"},
        {"title": "세 번째", "url": "https://example.com/2"},
    ]
