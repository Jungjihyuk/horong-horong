"""타임라인 주제 제안 단위 테스트.

사용자가 없는 주제를 지어내 요청하면 빈 타임라인이 나온다. 그래서 «리포트에 실제로
존재하는 주제만» 제시하는 것이 이 기능의 존재 이유다.
"""

import pytest

from timeline.suggest import category_id_for, suggest_topics


def write_report(reports_dir, date: str, sections) -> None:
    """(헤딩, 제목들) 목록으로 리포트 한 편을 만든다.

    제목 자리에 `(제목, URL)` 을 주면 그 URL 을 쓴다 — 여러 날에 «같은 기사» 가
    반복되는 상황을 재현하려면 URL 이 같아야 한다(중복 제거 키가 URL 이다).
    """
    blocks = ["# 뉴스 큐레이션 리포트 - " + date, "", "## 수집 현황", "- ✅ google_news: 사용", ""]
    for heading, titles in sections:
        blocks += [f"## {heading}", "🔑 키워드: 키워드", ""]
        for index, entry in enumerate(titles):
            title, url = entry if isinstance(entry, tuple) else (
                entry, f"https://example.com/{date}/{heading}/{index}"
            )
            blocks += [
                f"### {index + 1}. [{title}]({url})",
                f"> 중요도: {90 - index}/100 | 관련성: 90/100 | google_news | {date}",
                "",
            ]
    (reports_dir / f"{date}-0900.md").write_text("\n".join(blocks), encoding="utf-8")


# 하한이 «등장 리포트 5편 이상 · 2개월 이상» 이라 통과 케이스는 이만큼 필요하다.
FIVE_REPORT_DATES = [
    "2026-04-01", "2026-04-15", "2026-05-01", "2026-05-20", "2026-06-01",
]


@pytest.fixture()
def workspace(tmp_path):
    (tmp_path / "data" / "reports").mkdir(parents=True)
    return tmp_path


# 시나리오 1. 리포트에 실제로 있는 주제만 제안한다.
@pytest.mark.unit
def test_suggest_topics__returns_only_topics_present_in_reports(workspace):
    # Given: 금융 섹션이 3개월에 걸쳐 있는 리포트들.
    reports = workspace / "data" / "reports"
    for date in FIVE_REPORT_DATES:
        write_report(reports, date, [("금융/증시", [f"{date} 금리 기사"])])

    # When: 주제를 제안받는다.
    suggestions = suggest_topics(workspace.as_posix())

    # Then: 금리/거시경제 클러스터가 잡히고, 없는 주제는 나오지 않는다.
    labels = [item.label for item in suggestions]
    assert "금리/거시경제" in labels
    assert "AI/반도체" not in labels


# 시나리오 2. 재료가 부족한 주제는 제안하지 않는다.
@pytest.mark.unit
def test_suggest_topics__thin_topic__is_filtered_out(workspace):
    # Given: 리포트 한 편에만 등장하는 주제.
    reports = workspace / "data" / "reports"
    write_report(reports, "2026-04-01", [("금융/증시", ["단 하나의 기사"])])

    # When: 제안받는다.
    suggestions = suggest_topics(workspace.as_posix())

    # Then: 만들어도 읽을 것이 없으므로 빠진다(기본 하한 5편·사건 3건).
    assert suggestions == []


# 시나리오 3. 이미 만든 타임라인은 그렇다고 표시한다.
@pytest.mark.unit
def test_suggest_topics__existing_timeline__is_marked(workspace):
    # Given: 금융 리포트 3편과, 이미 만들어 둔 상태 파일.
    reports = workspace / "data" / "reports"
    for date in FIVE_REPORT_DATES:
        write_report(reports, date, [("금융/증시", [f"{date} 기사"])])
    state_dir = workspace / "data" / "timeline"
    state_dir.mkdir(parents=True)
    (state_dir / f"{category_id_for('금리/거시경제')}.json").write_text("{}", encoding="utf-8")

    # When: 제안받는다.
    macro = next(s for s in suggest_topics(workspace.as_posix()) if s.label == "금리/거시경제")

    # Then: 앱이 «만들기» 대신 «갱신» 을 보여줄 수 있다.
    assert macro.already_exists is True


# 시나리오 4. 온톨로지의 «기타» 버킷은 주제가 아니다.
@pytest.mark.unit
def test_suggest_topics__catch_all_bucket__is_excluded(workspace):
    # Given: 분류 실패분이 모이는 «기타» 섹션이 여러 달에 걸쳐 있다.
    reports = workspace / "data" / "reports"
    for date in FIVE_REPORT_DATES:
        write_report(reports, date, [("기타", [f"{date} 기사 A", f"{date} 기사 B"])])

    # When: 제안받는다.
    labels = [item.label for item in suggest_topics(workspace.as_posix())]

    # Then: 주제로 올리지 않는다.
    assert "기타" not in labels


# 시나리오 5. 같은 헤딩 묶음을 가리키는 후보는 하나만 남긴다.
@pytest.mark.unit
def test_suggest_topics__overlapping_headings__are_deduplicated(workspace):
    # Given: 부분일치로 서로를 잡아먹는 헤딩 두 개.
    reports = workspace / "data" / "reports"
    for date in FIVE_REPORT_DATES:
        write_report(reports, date, [
            ("부동산/토지", [f"{date} 토지 기사"]),
            ("부동산/상업시설", [f"{date} 상업시설 기사"]),
        ])

    # When: 제안받는다.
    estate = [s for s in suggest_topics(workspace.as_posix()) if "부동산" in s.label]

    # Then: 같은 것을 두 번 제시하지 않는다.
    assert len(estate) == 1


# 시나리오 6. 예상 호출 수를 알려준다 — 사용자가 비용을 알고 누른다.
@pytest.mark.unit
def test_suggest_topics__reports_estimated_llm_calls(workspace):
    # Given: 3개월치 금융 리포트.
    reports = workspace / "data" / "reports"
    for date in FIVE_REPORT_DATES:
        write_report(reports, date, [("금융/증시", [f"{date} 기사"])])

    # When: 제안받는다.
    macro = next(s for s in suggest_topics(workspace.as_posix()) if s.label == "금리/거시경제")

    # Then: 개월 수 + 개요 1회.
    assert macro.report_count == len(FIVE_REPORT_DATES)
    assert macro.month_count == 3
    assert macro.estimated_calls == 4


# 시나리오 N. 하한은 «등장 리포트 수» 로 잰다.
@pytest.mark.unit
def test_suggest_topics__below_report_threshold__is_filtered_out(workspace):
    # Given: 2개월에 걸쳐 있지만 리포트는 4편뿐인 주제.
    reports = workspace / "data" / "reports"
    for date in ["2026-04-01", "2026-04-10", "2026-05-01", "2026-05-10"]:
        write_report(reports, date, [("금융/증시", [f"{date} 기사"])])

    # When/Then: 기본 하한(5편) 미만이라 빠진다.
    assert suggest_topics(workspace.as_posix()) == []

    # 하한을 낮추면 잡힌다 — 값만 문제이지 로직은 아니다.
    lowered = suggest_topics(workspace.as_posix(), min_reports=4)
    assert [item.label for item in lowered] == ["금리/거시경제"]
    assert lowered[0].report_count == 4


# 시나리오 N+1. 한 달치만 있어도 만들 수 있다.
@pytest.mark.unit
def test_suggest_topics__single_month__is_allowed(workspace):
    """개월 수를 요구하지 않는다.

    2개월을 요구하면 새로 시작한 사용자는 두 달을 기다려야 아무것도 못 만든다.
    타임라인은 리포트가 늘 때마다 갱신되므로 한 달로 시작해 자라면 된다.
    """
    # Given: 전부 같은 달인 리포트 6편.
    reports = workspace / "data" / "reports"
    for day in range(1, 7):
        write_report(reports, f"2026-04-0{day}", [("금융/증시", [f"4월 {day}일 기사"])])

    # When/Then: 한 달짜리라도 제안된다.
    macro = next(s for s in suggest_topics(workspace.as_posix()) if s.label == "금리/거시경제")
    assert macro.month_count == 1
    assert macro.estimated_calls == 2  # 그 달 1회 + 개요 1회


# 시나리오 N+2. 파일은 많은데 사건이 없으면 뺀다.
@pytest.mark.unit
def test_suggest_topics__many_files_but_few_events__is_filtered_out(workspace):
    """개월 조건을 뺀 뒤 이 하한이 그 자리를 대신한다.

    같은 기사가 매일 재등장하면 파일 수는 늘지만 사건은 1건뿐이다. 실제 코퍼스의
    «구글»·«앤트로픽»(파일 9편 · 사건 1건)이 이 경우였다.
    """
    # Given: 6편 모두 같은 기사 하나만 담고 있다.
    reports = workspace / "data" / "reports"
    same = ("금융/증시", [("매일 반복되는 같은 기사", "https://example.com/same")])
    for day in range(1, 7):
        write_report(reports, f"2026-04-0{day}", [same])

    # When/Then: 파일은 6편이지만 사건이 1건이라 빠진다.
    assert suggest_topics(workspace.as_posix()) == []
    # 사건 하한만 낮추면 잡힌다 — 값의 문제이지 로직이 아니다.
    lowered = suggest_topics(workspace.as_posix(), min_events=1)
    assert lowered[0].report_count == 6
    assert lowered[0].event_count == 1


# 시나리오 N+3. 새 리포트가 없는 기존 타임라인은 has_updates가 False, 추가되면 True.
@pytest.mark.unit
def test_suggest_topics__existing_timeline_with_no_new_reports__has_updates_false(workspace):
    from datetime import datetime
    from contracts.timeline_artifact import MonthSynthesis, OverviewSynthesis
    from timeline.build import build_timeline

    class FakeProvider:
        def generate_json(self, _prompt, schema):
            if schema is MonthSynthesis:
                return MonthSynthesis(
                    summary="월 요약",
                    key_terms=["금리"],
                    axis=[],
                    assessments=[],
                )
            return OverviewSynthesis(
                summary="개요 요약",
                emphasis_keywords=["금리"],
                turning_points=[],
            )

    reports = workspace / "data" / "reports"
    for date in FIVE_REPORT_DATES:
        write_report(reports, date, [("금융/증시", [f"{date} 기사"])])

    fixed_now = datetime(2026, 6, 2)
    build_timeline(
        reports_dir=reports.as_posix(),
        output_dir=workspace.as_posix(),
        category_id=category_id_for("금리/거시경제"),
        category_label="금리/거시경제",
        provider=FakeProvider(),
        provider_name="test",
        now=fixed_now,
    )

    # When: 추가 리포트 없이 suggest_topics 호출
    suggestions = suggest_topics(workspace.as_posix(), now=fixed_now)
    macro = next(s for s in suggestions if s.label == "금리/거시경제")

    # Then: 변경사항 없음
    assert macro.already_exists is True
    assert macro.has_updates is False

    # When 2: 새 리포트 추가
    write_report(reports, "2026-06-05", [("금융/증시", ["6월 5일 신규 기사"])])
    suggestions_after = suggest_topics(workspace.as_posix(), now=fixed_now)
    macro_after = next(s for s in suggestions_after if s.label == "금리/거시경제")

    # Then 2: 갱신 필요
    assert macro_after.has_updates is True
