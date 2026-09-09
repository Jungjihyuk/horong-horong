"""월 종합과 개요 종합. 이 파이프라인에서 LLM 을 쓰는 유일한 곳이다.

vault 의 기존 생성기는 손으로 튜닝한 한국어 가중치표로 사건을 «고르기만» 했다. 그
방식은 거시경제에 맞춰져 있어 다른 카테고리로 넘어가면 무너지고, 무엇보다 「그 달에
무슨 일이 있었는가」를 문장으로 «종합» 하지는 못한다. 그 두 가지가 여기서 채워진다.

LLM 응답이 어긋나도(없는 event_id, 축 0개) 빌드가 멈추면 안 된다. 모든 선택에는
중요도 순 결정적 폴백이 있고, 폴백을 썼다는 사실은 호출부가 로그로 남긴다.
"""

from __future__ import annotations

from datetime import datetime

from contracts.timeline_artifact import (
    EventAssessment,
    MonthSynthesis,
    OverviewSynthesis,
    TimelineEvent,
    TimelineMonth,
    TimelineOverview,
    TurningPointSelection,
)
from timeline.state import MonthPlan, overview_input_hash

MAX_AXIS_EVENTS = 5


def build_month_prompt(
    category_label: str,
    month_key: str,
    events: list[TimelineEvent],
    *,
    axis_limit: int,
) -> str:
    """그 달 사건 전부를 주고 축 선정과 종합을 요구한다."""
    blocks: list[str] = []
    for event in events:
        bullets = "".join(f"\n    · {bullet}" for bullet in event.bullets)
        blocks.append(
            f"- event_id: {event.event_id}\n"
            f"  날짜: {event.date}\n"
            f"  리포트 중요도 참고값: {event.importance}\n"
            f"  제목: {event.title}{bullets}"
        )
    return "\n".join(
        [
            f"당신은 '{category_label}' 분야를 추적하는 애널리스트입니다.",
            f"아래는 {month_key} 한 달 동안 이 분야에서 수집된 사건 목록입니다.",
            "이 달에 무슨 일이 있었는지 종합하고, 흐름을 대표하는 축 사건을 고르세요.",
            "반드시 제공된 JSON schema에 맞춰 응답하세요.",
            "",
            "\n".join(blocks),
            "",
            "작성 기준:",
            "- summary는 이 달의 흐름을 설명하는 2~3문장. 사건 나열이 아니라 인과와 맥락을 쓸 것.",
            "- assessments는 모든 사건을 빠짐없이 평가할 것.",
            "- 중요도는 분야와 무관하게 다음 공통 배점을 적용할 것: 변화의 크기 0~25, "
            "파급 범위 0~25, 지속성 0~20, 이후 흐름을 바꾸는 힘 0~20, 근거 확실성 0~10.",
            "- assessment.reason은 위 항목들이 왜 그 점수인지 한 문장으로 설명할 것.",
            "- 같은 사실의 반복·후속 보도에는 같은 duplicate_group을 쓸 것. 원인과 결과처럼 "
            "서사적 역할이 다르면 같은 흐름이어도 서로 다른 그룹이다.",
            f"- axis는 이 달을 대표하는 사건 최대 {axis_limit}개. event_id는 위 목록에 있는 것만.",
            "- axis는 중요도를 우선하되 같은 duplicate_group을 반복 선택하지 말고, "
            "원인·변화·결과처럼 흐름에 고유한 정보를 보태는 사건을 고를 것.",
            "- 더 낮은 중요도의 사건을 axis로 고르면, 높은 점수 사건만으로 설명할 수 없는 "
            "서사적 역할을 axis[].why_it_matters에 명시할 것.",
            "- key_terms는 이 달의 핵심어 2~4개. 각각 «관세», «국채금리» 처럼 1~2단어의 짧은 명사구로.",
            "  문장이나 서술구(«~ 불확실성», «~가 재발») 는 쓰지 말 것.",
        ]
    )


def build_overview_prompt(category_label: str, months: list[TimelineMonth]) -> str:
    """개요는 월 요약만 본다. 원본 사건을 다시 넣지 않아 달이 늘어도 입력이 완만하게 는다."""
    blocks: list[str] = []
    for month in months:
        if not month.summary:
            continue
        events = "\n".join(
            f"  - event_id: {event.event_id} | 날짜: {event.date} | "
            f"중요도: {event.importance} | 제목: {event.title} | 대표 이유: {event.why_it_matters}"
            for event in month.axis_events
        )
        blocks.append(
            f"- {month.month_key}\n  핵심어: {', '.join(month.key_terms) or '-'}"
            f"\n  요약: {month.summary}\n  대표 사건:\n{events or '  - 없음'}"
        )
    return "\n".join(
        [
            f"아래는 '{category_label}' 분야의 월별 종합입니다.",
            "전체 기간을 관통하는 흐름을 정리하세요.",
            "반드시 제공된 JSON schema에 맞춰 응답하세요.",
            "",
            "\n".join(blocks),
            "",
            "작성 기준:",
            "- summary는 기간 전체의 흐름을 설명하는 2~3문장.",
            "- emphasis_keywords는 전체를 관통하는 키워드 3~6개. 각각 «기준금리», «물가» 처럼",
            "  1~2단어의 짧은 명사구로. 문장이나 수치 서술은 쓰지 말 것.",
            "- turning_points는 위 대표 사건 중 앞선 사건과 비교해 방향·정책·기대가 실제로 "
            "달라진 사건만 고를 것. 월별 최대 1개이며 근거가 없으면 고르지 말 것.",
            "- 표시 기간의 첫 사건이라는 이유만으로 전환점으로 고르지 말 것.",
            "- turning_points[].reason은 무엇이 어떻게 바뀌었는지 한 문장으로 쓸 것.",
        ]
    )


def _split_events(
    events: list[TimelineEvent],
    axis_ids: list[str],
    reasons: dict[str, str],
    assessments: dict[str, EventAssessment],
    *,
    axis_limit: int,
) -> tuple[list[TimelineEvent], list[TimelineEvent]]:
    """평가를 적용한 뒤 대표는 날짜순, 추가 사건은 중요도 내림차순으로 가른다."""
    assessed: list[TimelineEvent] = []
    groups: dict[str, str] = {}
    for event in events:
        result = assessments.get(event.event_id)
        if result is None:
            assessed.append(event)
            groups[event.event_id] = event.event_id
            continue
        assessed.append(event.model_copy(update={
            "importance": result.assessment.total,
            "importance_assessment": result.assessment,
        }))
        groups[event.event_id] = result.duplicate_group.strip() or event.event_id

    by_id = {event.event_id: event for event in assessed}
    chosen: list[TimelineEvent] = []
    chosen_groups: set[str] = set()
    proposed_groups: dict[str, list[TimelineEvent]] = {}
    group_order: list[str] = []
    for event_id in axis_ids:
        event = by_id.get(event_id)
        group = groups.get(event_id)
        if event is None or group is None:
            continue
        if group not in proposed_groups:
            proposed_groups[group] = []
            group_order.append(group)
        proposed_groups[group].append(event)

    for group in group_order:
        # 같은 사실의 반복을 둘 다 제안해도 더 중요하고 더 최신인 한 건만 대표로 남긴다.
        event = max(
            proposed_groups[group],
            key=lambda item: (item.importance, item.date, item.event_id),
        )
        chosen.append(event)
        chosen_groups.add(group)
        if len(chosen) == axis_limit:
            break
    if not chosen:
        # LLM 이 없는 id 를 주거나 대표를 하나도 못 고른 경우. 중복 그룹별 최고점으로 폴백한다.
        for event in sorted(assessed, key=lambda item: (-item.importance, item.date, item.event_id)):
            group = groups[event.event_id]
            if group in chosen_groups:
                continue
            chosen.append(event)
            chosen_groups.add(group)
            if len(chosen) == axis_limit:
                break

    chosen_ids = {event.event_id for event in chosen}
    axis = [
        event.model_copy(update={"why_it_matters": reasons.get(event.event_id, "")})
        for event in sorted(chosen, key=lambda item: item.date)
    ]
    rest = sorted(
        (event for event in assessed if event.event_id not in chosen_ids),
        key=lambda item: (-item.importance, item.date, item.event_id),
    )
    return axis, rest


def synthesize_month(
    provider,
    category_label: str,
    plan: MonthPlan,
    *,
    now: datetime,
    provider_name: str,
    prompt_version: int,
    axis_limit: int,
) -> TimelineMonth:
    """한 달을 종합한다. LLM 호출은 정확히 1회."""
    axis_limit = min(MAX_AXIS_EVENTS, max(1, axis_limit))
    prompt = build_month_prompt(
        category_label, plan.month_key, plan.events, axis_limit=axis_limit
    )
    result: MonthSynthesis = provider.generate_json(prompt, MonthSynthesis)

    reasons = {item.event_id: item.why_it_matters for item in result.axis}
    assessments = {item.event_id: item for item in result.assessments}
    axis, detail = _split_events(
        plan.events,
        [item.event_id for item in result.axis],
        reasons,
        assessments,
        axis_limit=axis_limit,
    )

    return TimelineMonth(
        month_key=plan.month_key,
        input_hash=plan.input_hash,
        synthesized_at=now.isoformat(timespec="seconds"),
        provider=provider_name,
        prompt_version=prompt_version,
        summary=result.summary.strip(),
        key_terms=[term.strip() for term in result.key_terms if term.strip()][:4],
        axis_events=axis,
        detail_events=detail,
    )


def synthesize_overview(
    provider,
    category_label: str,
    months: list[TimelineMonth],
    *,
    prompt_version: int,
) -> tuple[TimelineOverview, list[TurningPointSelection]]:
    """전체 개요를 만든다. LLM 호출은 정확히 1회."""
    prompt = build_overview_prompt(category_label, months)
    result: OverviewSynthesis = provider.generate_json(prompt, OverviewSynthesis)
    overview = TimelineOverview(
        input_hash=overview_input_hash(months, prompt_version=prompt_version),
        summary=result.summary.strip(),
        emphasis_keywords=[word.strip() for word in result.emphasis_keywords if word.strip()][:6],
    )
    return overview, result.turning_points


def apply_turning_points(
    months: list[TimelineMonth],
    selections: list[TurningPointSelection],
) -> list[TimelineMonth]:
    """유효한 대표 사건에만 월별 최대 1개의 전환점 근거를 붙인다."""
    all_axis = [event for month in months for event in month.axis_events]
    if not all_axis:
        return months

    # 조회 기간의 첫 사건은 앞선 비교 대상이 없어 흐름의 시작점일 뿐 전환점이 될 수 없다.
    first_event_id = min(all_axis, key=lambda item: (item.date, item.event_id)).event_id

    candidates: dict[str, tuple[str, TimelineEvent]] = {}
    for month in months:
        for event in month.axis_events:
            candidates[event.event_id] = (month.month_key, event)

    by_month: dict[str, list[tuple[TurningPointSelection, TimelineEvent]]] = {}
    for selection in selections:
        if selection.event_id == first_event_id:
            continue
        found = candidates.get(selection.event_id)
        reason = selection.reason.strip()
        if found is None or not reason:
            continue
        month_key, event = found
        by_month.setdefault(month_key, []).append((selection, event))

    chosen: dict[str, str] = {}
    for month_key, options in by_month.items():
        selection, _ = max(
            options,
            key=lambda pair: (
                pair[1].importance_assessment.trajectory_power
                if pair[1].importance_assessment else 0,
                pair[1].importance,
                pair[1].date,
                pair[1].event_id,
            ),
        )
        chosen[selection.event_id] = selection.reason.strip()

    return [
        month.model_copy(update={
            "axis_events": [
                event.model_copy(update={
                    "turning_point_reason": chosen.get(event.event_id, "")
                })
                for event in month.axis_events
            ],
            "detail_events": [
                event.model_copy(update={"turning_point_reason": ""})
                for event in month.detail_events
            ],
        })
        for month in months
    ]
