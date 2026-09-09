"""월간 타임라인 상태를 Markdown 문서로 렌더링한다.

Excalidraw 산출물과 같은 정보 구조를 따른다 — 머리말(기간·시점 수·개월 수·강조
키워드·전환점), 월별 컬럼(축 N · 세부 M · 핵심어), 축 카드, 우선순위순 세부 사건.
사람이 눈으로 종합 품질을 판정하는 가장 빠른 수단이라 먼저 만든다.
"""

from __future__ import annotations

import os
import tempfile

from contracts.timeline_artifact import TimelineEvent, TimelineState

def _short_date(date: str) -> str:
    """2026-04-10 → 04-10. 월 컬럼 안에서는 연도가 반복이라 지운다."""
    return date[5:] if len(date) >= 10 else date


def _render_axis_event(event: TimelineEvent, ordinal: int) -> list[str]:
    lines = [
        f"#### 대표 {ordinal}. {event.title}",
        f"`{_short_date(event.date)}` · 중요도 {event.importance}"
        + (f" · {' · '.join(event.tags)}" if event.tags else ""),
        "",
    ]
    lines += [f"- {bullet}" for bullet in event.bullets]
    if event.why_it_matters:
        lines += ["", f"> 대표 이유: {event.why_it_matters}"]
    if event.turning_point_reason:
        lines += ["", f"> 🔀 전환점: {event.turning_point_reason}"]
    if event.url:
        lines += ["", f"[원문]({event.url})"]
    return lines + [""]


def _render_detail_event(event: TimelineEvent) -> list[str]:
    head = (
        f"- **{_short_date(event.date)}** "
        f"`중요도 {event.importance}` — {event.title}"
    )
    lines = [head]
    lines += [f"  - {bullet}" for bullet in event.bullets]
    if event.tags:
        lines.append(f"  - 🏷 {' · '.join(event.tags)}")
    return lines


def render_timeline_markdown(state: TimelineState) -> str:
    """타임라인 상태 → Markdown 문서 전체."""
    total_events = sum(
        len(month.axis_events) + len(month.detail_events) for month in state.months
    )
    turning = [
        event for month in state.months for event in month.axis_events
        if event.turning_point_reason
    ]

    header = [
        f"# 📊 {state.category_label} — 월별 핵심 사건 타임라인",
        "",
        f"{state.date_from} ~ {state.date_to} · {total_events}개 시점 · "
        f"{len(state.months)}개월 · 월별 대표 최대 {state.axis_limit}개 · "
        f"전환점 {len(turning)}곳",
    ]
    if state.overview.emphasis_keywords:
        header += ["", f"🔎 강조: {' · '.join(state.overview.emphasis_keywords)}"]
    if state.overview.summary:
        header += ["", f"> {state.overview.summary}"]

    body: list[str] = []
    for month in state.months:
        body += [
            "",
            "---",
            "",
            f"## 📅 {month.month_key}",
            "",
            f"`대표 {len(month.axis_events)} · 추가 {len(month.detail_events)}`"
            + (f" · 핵심어 {' · '.join(month.key_terms)}" if month.key_terms else " · 핵심어 -"),
        ]
        if month.summary:
            body += ["", month.summary]
        body.append("")

        for ordinal, event in enumerate(month.axis_events, start=1):
            body += _render_axis_event(event, ordinal)

        body += ["##### 추가 사건 · 중요도순", ""]
        if month.detail_events:
            for event in month.detail_events:
                body += _render_detail_event(event)
        else:
            body.append("_추가 사건 없음_")

    generated = ["", "---", "", f"_생성: {state.generated_at}_"]
    return "\n".join(header + body + generated) + "\n"


def timeline_markdown_path(output_dir: str, category_id: str) -> str:
    return os.path.join(output_dir, "data", "timelines", f"{category_id}.md")


def write_timeline_markdown(output_dir: str, state: TimelineState) -> str:
    """렌더링해서 원자적으로 쓴다. 경로를 돌려준다."""
    path = timeline_markdown_path(output_dir, state.category_id)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=os.path.dirname(path), delete=False, suffix=".tmp"
    )
    try:
        with handle:
            handle.write(render_timeline_markdown(state))
        os.replace(handle.name, path)
    except BaseException:
        os.unlink(handle.name)
        raise
    return path
