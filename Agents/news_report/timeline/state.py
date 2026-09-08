"""타임라인 상태 파일 입출력과 «이 달을 다시 종합할 것인가» 판정.

이 모듈이 이 기능의 존재 이유다. 리포트가 하루 한두 편씩 늘어도 LLM 호출이 리포트
수에 비례하지 않게 막는 곳이 여기다.

봉인 여부를 파일에 저장하지 않는다. 이번 달은 다음 달이 되면 지난 달이라, 쓰기 없이
자정만 지나도 틀리는 파생 값이기 때문이다(CLAUDE.md R2). 대신 `synthesized_at` 과
`input_hash` 만 저장하고 판정은 읽는 시점에 계산한다. `now` 를 인자로 받는 것도
같은 이유다(R9) — 테스트가 달력에 의존하면 월말에만 깨진다.
"""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime

from contracts.timeline_artifact import (
    TIMELINE_PROMPT_VERSION,
    TimelineEvent,
    TimelineMonth,
    TimelineState,
)


def timeline_state_path(output_dir: str, category_id: str) -> str:
    return os.path.join(output_dir, "data", "timeline", f"{category_id}.json")


def load_state(path: str) -> TimelineState | None:
    """없거나 깨졌으면 None. 상태 파일은 캐시라서 못 읽으면 처음부터 다시 만들면 된다."""
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            return TimelineState.model_validate(json.load(handle))
    except (json.JSONDecodeError, ValueError, OSError):
        return None


def save_state(path: str, state: TimelineState) -> None:
    """원자적으로 쓴다. 중간에 죽어도 반쪽짜리 상태 파일이 남으면 안 된다."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    payload = json.dumps(state.model_dump(mode="json"), ensure_ascii=False, indent=2)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=os.path.dirname(path), delete=False, suffix=".tmp"
    )
    try:
        with handle:
            handle.write(payload + "\n")
        os.replace(handle.name, path)
    except BaseException:
        os.unlink(handle.name)
        raise


def month_key_of(date: str) -> str:
    return date[:7]


def current_month_key(now: datetime) -> str:
    return now.strftime("%Y-%m")


def is_sealed(month_key: str, now: datetime) -> bool:
    """지난 달은 봉인이다. 이번 달은 아직 사건이 더 붙을 수 있다."""
    return month_key < current_month_key(now)


def month_input_hash(events: list[TimelineEvent], *, prompt_version: int) -> str:
    """이 달을 다시 종합해야 하는지 판단하는 유일한 근거.

    LLM 입력에 실제로 들어가는 것만 넣는다. 여기 없는 값이 바뀌었다고 다시 종합하면
    「문서 1건 추가 = 호출 1~2회」 목표가 깨진다.
    """
    digest = hashlib.sha256()
    digest.update(f"prompt_version={prompt_version}\n".encode("utf-8"))
    for event in sorted(events, key=lambda item: (item.date, item.event_id)):
        digest.update(
            json.dumps(
                [event.event_id, event.date, event.title, event.importance,
                 event.bullets, event.tags],
                ensure_ascii=False,
                sort_keys=True,
            ).encode("utf-8")
        )
        digest.update(b"\n")
    return "sha256:" + digest.hexdigest()[:32]


def overview_input_hash(months: list[TimelineMonth], *, prompt_version: int) -> str:
    """개요는 원본 사건을 보지 않는다. 월 요약만 본다 — 달이 늘어도 입력이 월 수만큼만 는다."""
    digest = hashlib.sha256()
    digest.update(f"prompt_version={prompt_version}\n".encode("utf-8"))
    for month in sorted(months, key=lambda item: item.month_key):
        digest.update(
            json.dumps(
                [month.month_key, month.summary, month.key_terms, month.is_turning_point],
                ensure_ascii=False,
                sort_keys=True,
            ).encode("utf-8")
        )
        digest.update(b"\n")
    return "sha256:" + digest.hexdigest()[:32]


@dataclass(frozen=True)
class MonthPlan:
    """한 달을 어떻게 처리할지에 대한 결정과 그 근거."""

    month_key: str
    events: list[TimelineEvent]
    input_hash: str
    needs_synthesis: bool
    reason: str  # sealed / unchanged / backfill / new / changed / prompt-version


def group_by_month(events: list[TimelineEvent]) -> dict[str, list[TimelineEvent]]:
    grouped: dict[str, list[TimelineEvent]] = defaultdict(list)
    for event in events:
        grouped[month_key_of(event.date)].append(event)
    return {key: sorted(value, key=lambda item: item.date) for key, value in grouped.items()}


def plan_months(
    events: list[TimelineEvent],
    previous: TimelineState | None,
    *,
    now: datetime,
    prompt_version: int = TIMELINE_PROMPT_VERSION,
    rebuild: bool = False,
) -> list[MonthPlan]:
    """월별로 «다시 종합할 것인가» 를 정한다. LLM 은 아직 부르지 않는다.

    | 조건                                    | 결정 |
    |---|---|
    | 지난 달 + 이미 종합됨 + 프롬프트 동일   | 건너뛴다 (봉인) |
    | 지난 달 + 종합된 적 없음                | 종합 (최초 백필) |
    | 이번 달 + 입력 해시 동일                | 건너뛴다 |
    | 이번 달 + 입력 해시 변경                | 다시 종합 |
    """
    known = {month.month_key: month for month in (previous.months if previous else [])}
    plans: list[MonthPlan] = []

    for month_key, month_events in sorted(group_by_month(events).items()):
        digest = month_input_hash(month_events, prompt_version=prompt_version)
        existing = known.get(month_key)

        if rebuild:
            reason, needs = "rebuild", True
        elif existing is None or not existing.synthesized_at:
            # 봉인된 달이라도 종합된 적이 없으면 한 번은 해야 한다(최초 백필).
            reason, needs = "backfill" if is_sealed(month_key, now) else "new", True
        elif existing.prompt_version != prompt_version:
            reason, needs = "prompt-version", True
        elif is_sealed(month_key, now):
            # 봉인. 뒤늦게 과거 달 사건이 들어와도 다시 계산하지 않는다 —
            # 되살리려면 --rebuild 를 명시해야 한다.
            reason, needs = "sealed", False
        elif existing.input_hash == digest:
            reason, needs = "unchanged", False
        else:
            reason, needs = "changed", True

        plans.append(
            MonthPlan(
                month_key=month_key,
                events=month_events,
                input_hash=digest,
                needs_synthesis=needs,
                reason=reason,
            )
        )
    return plans


def carry_over(previous: TimelineState | None, month_key: str) -> TimelineMonth | None:
    """다시 종합하지 않기로 한 달의 기존 결과를 그대로 가져온다."""
    if previous is None:
        return None
    for month in previous.months:
        if month.month_key == month_key:
            return month
    return None
