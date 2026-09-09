"""타임라인 주제 제안 단위 테스트.

사용자가 없는 주제를 지어내 요청하면 빈 타임라인이 나온다. 그래서 «리포트에 실제로
존재하는 주제만» 제시하는 것이 이 기능의 존재 이유다.
"""

import pytest

from timeline.suggest import category_id_for, suggest_topics


def write_report(reports_dir, date: str, sections: list[tuple[str, list[str]]]) -> None:
    """(헤딩, 제목들) 목록으로 리포트 한 편을 만든다."""
    blocks = ["# 뉴스 큐레이션 리포트 - " + date, "", "## 수집 현황", "- ✅ google_news: 사용", ""]
    for heading, titles in sections:
        blocks += [f"## {heading}", "🔑 키워드: 키워드", ""]
        for index, title in enumerate(titles):
            blocks += [
                f"### {index + 1}. [{title}](https://example.com/{date}/{heading}/{index})",
                f"> 중요도: {90 - index}/100 | 관련성: 90/100 | google_news | {date}",
                "",
            ]
    (reports_dir / f"{date}-0900.md").write_text("\n".join(blocks), encoding="utf-8")


@pytest.fixture()
def workspace(tmp_path):
    (tmp_path / "data" / "reports").mkdir(parents=True)
    return tmp_path


# 시나리오 1. 리포트에 실제로 있는 주제만 제안한다.
@pytest.mark.unit
def test_suggest_topics__returns_only_topics_present_in_reports(workspace):
    # Given: 금융 섹션이 3개월에 걸쳐 있는 리포트들.
    reports = workspace / "data" / "reports"
    for date in ["2026-04-01", "2026-05-01", "2026-06-01"]:
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
    # Given: 한 달에 한 건만 있는 주제.
    reports = workspace / "data" / "reports"
    write_report(reports, "2026-04-01", [("금융/증시", ["단 하나의 기사"])])

    # When: 제안받는다.
    suggestions = suggest_topics(workspace.as_posix())

    # Then: 만들어도 읽을 것이 없으므로 빠진다(기본 하한 3건·2개월).
    assert suggestions == []


# 시나리오 3. 이미 만든 타임라인은 그렇다고 표시한다.
@pytest.mark.unit
def test_suggest_topics__existing_timeline__is_marked(workspace):
    # Given: 금융 리포트 3편과, 이미 만들어 둔 상태 파일.
    reports = workspace / "data" / "reports"
    for date in ["2026-04-01", "2026-05-01", "2026-06-01"]:
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
    for date in ["2026-04-01", "2026-05-01", "2026-06-01"]:
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
    for date in ["2026-04-01", "2026-05-01", "2026-06-01"]:
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
    for date in ["2026-04-01", "2026-05-01", "2026-06-01"]:
        write_report(reports, date, [("금융/증시", [f"{date} 기사"])])

    # When: 제안받는다.
    macro = next(s for s in suggest_topics(workspace.as_posix()) if s.label == "금리/거시경제")

    # Then: 개월 수 + 개요 1회.
    assert macro.month_count == 3
    assert macro.estimated_calls == 4
