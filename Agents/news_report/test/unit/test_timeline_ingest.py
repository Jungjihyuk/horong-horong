"""리포트 마크다운 → 시점 사건 수집 단위 테스트."""

import pytest

from timeline.ingest import (
    article_key,
    canonical_url,
    clean_title,
    collect_events,
    heading_matches,
    query_terms,
)


def write_report(reports_dir, date: str, heading: str, items: list[tuple[str, str]],
                 trend: str = "") -> None:
    body = "\n\n".join(
        f"### {index + 1}. [{title}]({url})\n"
        f"> 중요도: {90 - index}/100 | 관련성: 90/100 | google_news | {date}"
        for index, (title, url) in enumerate(items)
    )
    trend_line = f"📈 트렌드: {trend}\n" if trend else ""
    (reports_dir / f"{date}-0900.md").write_text(
        f"# 뉴스 큐레이션 리포트 - {date}\n\n"
        f"## 수집 현황\n- ✅ google_news: {len(items)}개 사용\n\n"
        f"## {heading}\n🔑 키워드: 금리, 물가\n{trend_line}\n{body}\n",
        encoding="utf-8",
    )


@pytest.fixture()
def reports_dir(tmp_path):
    path = tmp_path / "reports"
    path.mkdir()
    return path


# 시나리오 1. 헤딩 명칭이 리포트마다 달라도 같은 카테고리로 묶인다.
@pytest.mark.unit
def test_heading_matches__alias_cluster__matches_sibling_headings():
    # Given: "금리/거시경제" 로 질의한다.
    terms = query_terms("금리/거시경제")

    # When/Then: 같은 별칭 클러스터의 헤딩이 모두 걸린다.
    assert heading_matches("금융/증시", terms)
    assert heading_matches("거시경제", terms)
    assert heading_matches("환율", terms)
    # 다른 클러스터는 걸리지 않는다.
    assert not heading_matches("AI 기업/모델", terms)


# 시나리오 2. 실행 메타 섹션은 사건으로 세지 않는다.
@pytest.mark.unit
def test_heading_matches__collection_status_section__is_skipped():
    # Given/When/Then: "수집 현황" 은 어떤 질의로도 매칭되지 않는다.
    assert not heading_matches("수집 현황", query_terms("금리"))


# 시나리오 3. 같은 기사가 다음 날 다시 실려도 처음 나온 날에만 붙는다.
@pytest.mark.unit
def test_collect_events__article_repeated_next_day__counts_only_first_day(reports_dir):
    # Given: 같은 URL 의 기사가 이틀 연속 리포트에 실렸고, 둘째 날에만 새 기사가 있다.
    repeated = ("금리 동결 결정", "https://example.com/a")
    write_report(reports_dir, "2026-05-01", "금융/증시", [repeated])
    write_report(reports_dir, "2026-05-02", "금융/증시", [repeated, ("새 기사", "https://example.com/b")])

    # When: 사건을 모은다.
    events = collect_events(str(reports_dir), "macro", query_terms("금리/거시경제"))

    # Then: 둘째 날 사건의 대표 제목은 반복된 기사가 아니라 새 기사다.
    assert [event.date for event in events] == ["2026-05-01", "2026-05-02"]
    assert events[1].title == "새 기사"


# 시나리오 4. 새 기사가 하나도 없는 날은 사건을 만들지 않는다.
@pytest.mark.unit
def test_collect_events__all_articles_already_seen__produces_no_event(reports_dir):
    # Given: 이틀 모두 완전히 같은 기사 목록이다.
    same = [("금리 동결 결정", "https://example.com/a")]
    write_report(reports_dir, "2026-05-01", "금융/증시", same)
    write_report(reports_dir, "2026-05-02", "금융/증시", same)

    # When: 사건을 모은다.
    events = collect_events(str(reports_dir), "macro", query_terms("금리/거시경제"))

    # Then: 첫날만 남는다.
    assert [event.date for event in events] == ["2026-05-01"]


# 시나리오 5. 트렌드 문장이 있으면 그것이 대표 제목이 되고 기사 제목은 불릿이 된다.
@pytest.mark.unit
def test_collect_events__trend_present__uses_trend_as_headline(reports_dir):
    # Given: 트렌드 요약이 있는 리포트 1편.
    write_report(
        reports_dir,
        "2026-05-01",
        "금융/증시",
        [("첫 기사", "https://example.com/a"), ("둘째 기사", "https://example.com/b")],
        trend="관세 무효화 판결이 시장 전반을 흔들었습니다.",
    )

    # When: 사건을 모은다.
    events = collect_events(str(reports_dir), "macro", query_terms("금리/거시경제"))

    # Then: 제목은 트렌드 첫 문장, 불릿은 기사 제목들이다.
    assert events[0].title == "관세 무효화 판결이 시장 전반을 흔들었습니다."
    assert events[0].bullets == ["첫 기사", "둘째 기사"]


# 시나리오 6. 중요도는 제목 바로 아래 인용 줄에서 읽는다.
@pytest.mark.unit
def test_collect_events__importance_line__is_parsed(reports_dir):
    # Given: 중요도 90/89 인 기사 두 건.
    write_report(
        reports_dir, "2026-05-01", "금융/증시",
        [("첫 기사", "https://example.com/a"), ("둘째 기사", "https://example.com/b")],
    )

    # When: 사건을 모은다.
    events = collect_events(str(reports_dir), "macro", query_terms("금리/거시경제"))

    # Then: 그날의 최대 중요도가 사건 중요도가 된다.
    assert events[0].importance == 90


# 시나리오 7. 편집 프리픽스와 언론사 꼬리를 제목에서 걷어낸다.
@pytest.mark.unit
def test_clean_title__editorial_prefix_and_outlet_suffix__are_stripped():
    # Given/When/Then
    assert clean_title("[속보] 금리 동결 - 머니투데이") == "금리 동결"
    assert clean_title("〔김종학의 뉴욕증시〕 관세 판결") == "관세 판결"


# 시나리오 8. Google News URL 은 query 에 기사 식별자가 있으므로 보존해야 한다.
@pytest.mark.unit
def test_canonical_url__query_string__is_preserved():
    # Given: query 로만 구분되는 두 기사.
    first = "https://news.google.com/rss/articles/CBMiAAA?oc=5"
    second = "https://news.google.com/rss/articles/CBMiBBB?oc=5"

    # When/Then: query 를 지우면 같은 기사가 되어버리므로 남아 있어야 한다.
    assert canonical_url(first) != canonical_url(second)
    assert article_key("제목", first) != article_key("제목", second)


# 시나리오 9. URL 이 없으면 정규화한 제목이 중복 키가 된다.
@pytest.mark.unit
def test_article_key__missing_url__falls_back_to_title():
    # Given/When/Then: 공백·대소문자 차이는 같은 기사로 본다.
    assert article_key("금리 동결 결정", "") == article_key("금리동결결정", "")
