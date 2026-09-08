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
    MonthSynthesis,
    OverviewSynthesis,
    TimelineEvent,
    TimelineMonth,
    TimelineOverview,
)
from timeline.state import MonthPlan, overview_input_hash

MAX_AXIS_EVENTS = 3


def build_month_prompt(category_label: str, month_key: str, events: list[TimelineEvent]) -> str:
    """그 달 사건 전부를 주고 축 선정과 종합을 요구한다."""
    blocks: list[str] = []
    for event in events:
        bullets = "".join(f"\n    · {bullet}" for bullet in event.bullets)
        blocks.append(
            f"- event_id: {event.event_id}\n"
            f"  날짜: {event.date}\n"
            f"  중요도: {event.importance}\n"
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
            f"- axis는 이 달을 대표하는 사건 최대 {MAX_AXIS_EVENTS}개. event_id는 위 목록에 있는 것만.",
            "- axis[].why_it_matters는 '왜 이것이 이 달의 축인가'를 한 문장으로.",
            "- key_terms는 이 달의 핵심어 2~4개. 각각 «관세», «국채금리» 처럼 1~2단어의 짧은 명사구로.",
            "  문장이나 서술구(«~ 불확실성», «~가 재발») 는 쓰지 말 것.",
            "- is_turning_point는 이 달이 이전 흐름과 끊기는 전환점이면 true.",
        ]
    )


def build_overview_prompt(category_label: str, months: list[TimelineMonth]) -> str:
    """개요는 월 요약만 본다. 원본 사건을 다시 넣지 않아 달이 늘어도 입력이 완만하게 는다."""
    blocks = [
        f"- {month.month_key}"
        f"{' (전환점)' if month.is_turning_point else ''}"
        f"\n  핵심어: {', '.join(month.key_terms) or '-'}"
        f"\n  요약: {month.summary}"
        for month in months
        if month.summary
    ]
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
        ]
    )


def _split_events(
    events: list[TimelineEvent],
    axis_ids: list[str],
    reasons: dict[str, str],
) -> tuple[list[TimelineEvent], list[TimelineEvent]]:
    """축/세부로 가른다. 축은 날짜순, 세부는 중요도 내림차순으로 순위를 매긴다."""
    by_id = {event.event_id: event for event in events}
    chosen = [by_id[event_id] for event_id in axis_ids if event_id in by_id][:MAX_AXIS_EVENTS]
    if not chosen:
        # LLM 이 없는 id 를 주거나 축을 하나도 못 고른 경우. 중요도 순으로 결정적 폴백.
        chosen = sorted(events, key=lambda item: (-item.importance, item.date))[:MAX_AXIS_EVENTS]

    chosen_ids = {event.event_id for event in chosen}
    axis = [
        event.model_copy(update={"why_it_matters": reasons.get(event.event_id, ""), "rank": None})
        for event in sorted(chosen, key=lambda item: item.date)
    ]
    rest = sorted(
        (event for event in events if event.event_id not in chosen_ids),
        key=lambda item: (-item.importance, item.date),
    )
    # 순위는 그 달 전체 기준이다. 축이 1~N 을 차지하므로 세부는 N+1 부터 이어간다.
    offset = len(axis)
    detail = [
        event.model_copy(update={"rank": offset + index + 1})
        for index, event in enumerate(rest)
    ]
    return axis, detail


def synthesize_month(
    provider,
    category_label: str,
    plan: MonthPlan,
    *,
    now: datetime,
    provider_name: str,
    prompt_version: int,
) -> TimelineMonth:
    """한 달을 종합한다. LLM 호출은 정확히 1회."""
    prompt = build_month_prompt(category_label, plan.month_key, plan.events)
    result: MonthSynthesis = provider.generate_json(prompt, MonthSynthesis)

    reasons = {item.event_id: item.why_it_matters for item in result.axis}
    axis, detail = _split_events(plan.events, [item.event_id for item in result.axis], reasons)

    return TimelineMonth(
        month_key=plan.month_key,
        input_hash=plan.input_hash,
        synthesized_at=now.isoformat(timespec="seconds"),
        provider=provider_name,
        prompt_version=prompt_version,
        summary=result.summary.strip(),
        key_terms=[term.strip() for term in result.key_terms if term.strip()][:4],
        is_turning_point=result.is_turning_point,
        axis_events=axis,
        detail_events=detail,
    )


def synthesize_overview(
    provider,
    category_label: str,
    months: list[TimelineMonth],
    *,
    prompt_version: int,
) -> TimelineOverview:
    """전체 개요를 만든다. LLM 호출은 정확히 1회."""
    prompt = build_overview_prompt(category_label, months)
    result: OverviewSynthesis = provider.generate_json(prompt, OverviewSynthesis)
    return TimelineOverview(
        input_hash=overview_input_hash(months, prompt_version=prompt_version),
        summary=result.summary.strip(),
        emphasis_keywords=[word.strip() for word in result.emphasis_keywords if word.strip()][:6],
        turning_point_count=sum(1 for month in months if month.is_turning_point),
    )
