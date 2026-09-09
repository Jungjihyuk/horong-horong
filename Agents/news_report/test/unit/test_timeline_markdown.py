"""월간 타임라인 Markdown 렌더링 단위 테스트."""

import pytest

from contracts.timeline_artifact import (
    TimelineEvent,
    TimelineMonth,
    TimelineOverview,
    TimelineState,
)
from renderers.timeline_markdown import render_timeline_markdown


def make_event(event_id: str, date: str, title: str, **kwargs) -> TimelineEvent:
    return TimelineEvent(event_id=event_id, date=date, title=title, **kwargs)


def make_state(months: list[TimelineMonth], **overview_kwargs) -> TimelineState:
    return TimelineState(
        category_id="macro",
        category_label="거시경제",
        date_from="2026-02-22",
        date_to="2026-04-30",
        generated_at="2026-09-08T21:00:00",
        overview=TimelineOverview(**overview_kwargs),
        months=months,
    )


# 시나리오 1. 월 헤더에 축/세부 개수와 핵심어가 함께 나온다.
@pytest.mark.unit
def test_render_timeline_markdown__month_with_axis_and_details__shows_counts_and_terms():
    # Given: 축 1개 · 세부 2개인 달.
    month = TimelineMonth(
        month_key="2026-04",
        input_hash="x",
        key_terms=["상승", "유가"],
        axis_events=[make_event("a1", "2026-04-10", "축 사건")],
        detail_events=[
            make_event("d1", "2026-04-08", "세부 1"),
            make_event("d2", "2026-04-16", "세부 2"),
        ],
    )

    # When: 렌더링한다.
    rendered = render_timeline_markdown(make_state([month]))

    # Then: 목업과 같은 «축 N · 세부 M» 표기와 핵심어가 보인다.
    assert "`대표 1 · 추가 2`" in rendered
    assert "핵심어 상승 · 유가" in rendered


# 시나리오 2. 세부 사건이 없는 달은 «세부 사건 없음» 을 명시한다.
@pytest.mark.unit
def test_render_timeline_markdown__month_without_details__renders_empty_state():
    # Given: 축만 있고 세부가 없는 달.
    month = TimelineMonth(
        month_key="2026-02",
        input_hash="x",
        axis_events=[make_event("a1", "2026-02-22", "축 사건")],
    )

    # When: 렌더링한다.
    rendered = render_timeline_markdown(make_state([month]))

    # Then: 빈 목록이 아니라 «없음» 이라고 말한다.
    assert "_추가 사건 없음_" in rendered
    assert "`대표 1 · 추가 0`" in rendered


# 시나리오 3. 머리말에 기간·시점 수·개월 수·전환점 수가 모두 들어간다.
@pytest.mark.unit
def test_render_timeline_markdown__header__summarizes_range_and_turning_points():
    # Given: 2개월이고 그중 하나가 전환점이다.
    months = [
        TimelineMonth(
            month_key="2026-02", input_hash="x",
            axis_events=[make_event("a1", "2026-02-22", "축")],
        ),
        TimelineMonth(
            month_key="2026-03", input_hash="y",
            axis_events=[make_event(
                "a2", "2026-03-30", "축",
                turning_point_reason="금리 인하 기대가 긴축 우려로 바뀌었다.",
            )],
            detail_events=[make_event("d1", "2026-03-28", "세부")],
        ),
    ]

    # When: 렌더링한다.
    rendered = render_timeline_markdown(
        make_state(months, emphasis_keywords=["기준금리", "물가"], summary="전체 흐름.")
    )

    # Then: 머리말이 목업의 요약 줄을 재현한다.
    assert "2026-02-22 ~ 2026-04-30 · 3개 시점 · 2개월 · 월별 대표 최대 3개 · 전환점 1곳" in rendered
    assert "🔎 강조: 기준금리 · 물가" in rendered
    assert "🔀 전환점: 금리 인하 기대가 긴축 우려로 바뀌었다." in rendered


# 시나리오 4. 축 사건의 «왜 축인가» 와 세부 사건의 순위가 표시된다.
@pytest.mark.unit
def test_render_timeline_markdown__axis_reason_and_detail_rank__are_rendered():
    # Given: 근거가 달린 축 1개와 4순위 세부 1개.
    month = TimelineMonth(
        month_key="2026-04",
        input_hash="x",
        axis_events=[
            make_event("a1", "2026-04-10", "CPI 발표", importance=93,
                       why_it_matters="물가 경로가 여기서 갈렸다.")
        ],
        detail_events=[make_event("d1", "2026-04-08", "휴전 기대", importance=83)],
    )

    # When: 렌더링한다.
    rendered = render_timeline_markdown(make_state([month]))

    # Then: 근거는 인용으로, 순위는 세부 줄에 붙는다.
    assert "> 대표 이유: 물가 경로가 여기서 갈렸다." in rendered
    assert "`중요도 83`" in rendered
    assert "`04-10` · 중요도 93" in rendered
