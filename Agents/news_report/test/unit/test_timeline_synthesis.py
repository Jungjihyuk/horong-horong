"""타임라인 중요도·대표 사건·전환점 정규화 테스트."""

import pytest

from contracts.timeline_artifact import (
    EventAssessment,
    ImportanceAssessment,
    TimelineEvent,
    TimelineMonth,
    TurningPointSelection,
)
from timeline.synthesize import (
    _split_events,
    apply_turning_points,
    build_month_prompt,
    build_overview_prompt,
)


def assessment(event_id: str, group: str, *, change: int, trajectory: int):
    return EventAssessment(
        event_id=event_id,
        duplicate_group=group,
        assessment=ImportanceAssessment(
            change_magnitude=change,
            impact_scope=25,
            durability=20,
            trajectory_power=trajectory,
            evidence_strength=5,
            reason=f"{event_id} 평가 근거",
        ),
    )


@pytest.mark.unit
def test_split_events__duplicate_representatives__keeps_higher_scored_event():
    events = [
        TimelineEvent(event_id="start", date="2026-09-05", title="긴축 우려의 출발"),
        TimelineEvent(event_id="yield-92", date="2026-09-08", title="10년물 5% 접근"),
        TimelineEvent(event_id="yield-95", date="2026-09-09", title="10년물 5% 시험"),
    ]
    scores = {
        item.event_id: item
        for item in [
            assessment("start", "oil-and-jobs", change=12, trajectory=15),
            assessment("yield-92", "ten-year-five-percent", change=25, trajectory=17),
            assessment("yield-95", "ten-year-five-percent", change=25, trajectory=20),
        ]
    }

    axis, detail = _split_events(
        events,
        ["start", "yield-92", "yield-95"],
        {event.event_id: f"{event.event_id} 대표 이유" for event in events},
        scores,
        axis_limit=3,
    )

    assert [event.event_id for event in axis] == ["start", "yield-95"]
    assert [event.event_id for event in detail] == ["yield-92"]
    assert axis[-1].importance == 95
    assert detail[0].importance == 92


@pytest.mark.unit
def test_apply_turning_points__multiple_in_month__keeps_stronger_trajectory_change():
    baseline = TimelineEvent(
        event_id="baseline", date="2026-09-01", title="기준 사건", importance=80,
    )
    lower = TimelineEvent(
        event_id="lower", date="2026-09-06", title="정책 발언", importance=90,
        importance_assessment=assessment(
            "lower", "policy", change=25, trajectory=12
        ).assessment,
    )
    stronger = TimelineEvent(
        event_id="stronger", date="2026-09-09", title="금리 경로 변화", importance=85,
        importance_assessment=assessment(
            "stronger", "rates", change=20, trajectory=20
        ).assessment,
    )
    month = TimelineMonth(
        month_key="2026-09", input_hash="hash", axis_events=[baseline, lower, stronger]
    )

    result = apply_turning_points(
        [month],
        [
            TurningPointSelection(event_id="lower", reason="낮은 전환력"),
            TurningPointSelection(event_id="stronger", reason="기대가 긴축으로 바뀌었다"),
            TurningPointSelection(event_id="missing", reason="없는 사건"),
        ],
    )

    marked = [event for event in result[0].axis_events if event.turning_point_reason]
    assert [(event.event_id, event.turning_point_reason) for event in marked] == [
        ("stronger", "기대가 긴축으로 바뀌었다")
    ]


@pytest.mark.unit
def test_apply_turning_points__first_event_in_window__excluded_even_if_selected():
    first = TimelineEvent(
        event_id="first", date="2026-09-01", title="첫 대표 사건", importance=99,
        importance_assessment=assessment(
            "first", "start", change=25, trajectory=20
        ).assessment,
    )
    second = TimelineEvent(
        event_id="second", date="2026-09-15", title="두 번째 사건", importance=80,
        importance_assessment=assessment(
            "second", "continuation", change=20, trajectory=18
        ).assessment,
    )
    month = TimelineMonth(
        month_key="2026-09", input_hash="hash", axis_events=[first, second]
    )

    result = apply_turning_points(
        [month],
        [
            TurningPointSelection(event_id="first", reason="기간의 시작 사건"),
            TurningPointSelection(event_id="second", reason="흐름의 본격적인 변곡점"),
        ],
    )

    marked = [event for event in result[0].axis_events if event.turning_point_reason]
    assert [(event.event_id, event.turning_point_reason) for event in marked] == [
        ("second", "흐름의 본격적인 변곡점")
    ]


@pytest.mark.unit
def test_apply_turning_points__single_event_in_timeline__never_marked():
    only = TimelineEvent(
        event_id="only", date="2026-09-01", title="유일한 사건", importance=90,
    )
    month = TimelineMonth(
        month_key="2026-09", input_hash="hash", axis_events=[only]
    )
    result = apply_turning_points(
        [month],
        [TurningPointSelection(event_id="only", reason="유일한 사건")],
    )
    assert result[0].axis_events[0].turning_point_reason == ""


@pytest.mark.unit
def test_prompts__publish_shared_rubric_and_event_level_turning_point_rules():
    event = TimelineEvent(event_id="event", date="2026-09-09", title="사건")
    month_prompt = build_month_prompt(
        "금리/거시경제", "2026-09", [event], axis_limit=5
    )
    overview_prompt = build_overview_prompt(
        "금리/거시경제",
        [TimelineMonth(
            month_key="2026-09", input_hash="hash", summary="월 요약",
            axis_events=[event],
        )],
    )

    assert "변화의 크기 0~25" in month_prompt
    assert "axis는 이 달을 대표하는 사건 최대 5개" in month_prompt
    assert "월별 최대 1개" in overview_prompt
    assert "표시 기간의 첫 사건이라는 이유만으로" in overview_prompt
