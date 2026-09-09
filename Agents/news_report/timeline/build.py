"""타임라인 한 편을 만든다 — 수집 → 월 계획 → 필요한 달만 종합 → 개요 → 저장.

여기에 분기라고 할 만한 것은 「이 달을 다시 종합하나」 하나뿐이고, 그 판단은 이미
`state.plan_months` 가 끝내둔다. 그래서 graph engine 이 아니라 함수 호출로 충분하다
(`docs/…/뉴스탭/langgraph-adoption-boundary-for-news-research.md` 의 도입 기준 참고).

각 단계를 `상태 → 상태 조각` 순수 함수로 유지하는 이유는, 나중에 critique 루프나
사용자 승인(HITL)이 실제로 생겨 LangGraph 를 도입할 때 이 함수들이 그대로 node 본문이
되게 하기 위해서다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable

from contracts.timeline_artifact import (
    TIMELINE_PROMPT_VERSION,
    TIMELINE_SCHEMA_VERSION,
    TimelineMonth,
    TimelineOverview,
    TimelineState,
    TurningPointSelection,
)
from timeline.ingest import collect_events, query_terms
from timeline.state import (
    MonthPlan,
    carry_over,
    load_state,
    overview_input_hash,
    plan_months,
    save_state,
    timeline_state_path,
)
from timeline.synthesize import apply_turning_points, synthesize_month, synthesize_overview


@dataclass
class BuildResult:
    """무엇을 했고 LLM 을 몇 번 불렀는지. 점진성 검증이 이 숫자를 본다."""

    category_id: str
    category_label: str
    state: TimelineState
    plans: list[MonthPlan] = field(default_factory=list)
    month_calls: int = 0
    overview_calls: int = 0
    state_path: str = ""

    @property
    def total_calls(self) -> int:
        return self.month_calls + self.overview_calls

    @property
    def projected_calls(self) -> int:
        """dry-run 에서 «실제로 돌리면 몇 번 부를까». 비용을 미리 보는 용도다."""
        months = sum(1 for plan in self.plans if plan.needs_synthesis)
        return months + (1 if months else 0)


def build_timeline(
    *,
    reports_dir: str,
    output_dir: str,
    category_id: str,
    category_label: str,
    provider,
    provider_name: str,
    now: datetime,
    since: str | None = None,
    until: str | None = None,
    rebuild: bool = False,
    dry_run: bool = False,
    prompt_version: int = TIMELINE_PROMPT_VERSION,
    axis_limit: int = 3,
    log: Callable[[str], None] = lambda _message: None,
) -> BuildResult:
    axis_limit = min(5, max(1, axis_limit))
    events = collect_events(
        reports_dir, category_id, query_terms(category_label), since=since, until=until
    )
    path = timeline_state_path(output_dir, category_id)
    previous = load_state(path)
    plans = plan_months(
        events,
        previous,
        now=now,
        prompt_version=prompt_version,
        axis_limit=axis_limit,
        rebuild=rebuild,
    )

    log(
        f"[{category_label}] 사건 {len(events)}건 / {len(plans)}개월 · "
        f"재종합 대상 {sum(1 for plan in plans if plan.needs_synthesis)}개월"
    )

    months: list[TimelineMonth] = []
    warnings: list[str] = []
    month_calls = 0
    for plan in plans:
        if not plan.needs_synthesis:
            existing = carry_over(previous, plan.month_key)
            if existing is not None:
                log(f"  {plan.month_key}  건너뜀 ({plan.reason})")
                months.append(existing)
                continue
            # 여기 오면 계획과 상태가 어긋난 것이다. 비싼 쪽이 아니라 안전한 쪽을 고른다.
            log(f"  {plan.month_key}  상태 없음 — 다시 종합한다")

        if dry_run:
            log(f"  {plan.month_key}  [dry-run] 종합 예정 ({plan.reason})")
            months.append(
                carry_over(previous, plan.month_key)
                or TimelineMonth(month_key=plan.month_key, input_hash=plan.input_hash)
            )
            continue

        log(f"  {plan.month_key}  종합 ({plan.reason}) · 사건 {len(plan.events)}건")
        try:
            months.append(
                synthesize_month(
                    provider,
                    category_label,
                    plan,
                    now=now,
                    provider_name=provider_name,
                    prompt_version=prompt_version,
                    axis_limit=axis_limit,
                )
            )
        except Exception as error:  # noqa: BLE001 — 어떤 실패든 나머지 달은 살린다
            # 한 달이 실패했다고 이번 실행 전체를 버리면, 8개월 백필 중 마지막에
            # 실패했을 때 앞의 7개월 호출이 통째로 낭비된다. 실패한 달만 «종합 안 됨»
            # 으로 남기면 `synthesized_at` 이 비어 있으므로 다음 실행이 그 달만 다시 잡는다.
            message = f"{plan.month_key} 종합 실패: {type(error).__name__}: {error}"
            log(f"  {plan.month_key}  실패 — 건너뛰고 계속한다 ({type(error).__name__})")
            warnings.append(message)
            months.append(
                carry_over(previous, plan.month_key)
                or TimelineMonth(month_key=plan.month_key, input_hash="")
            )
        month_calls += 1

    try:
        overview, turning_points, overview_calls = _resolve_overview(
            provider=provider,
            category_label=category_label,
            months=months,
            previous=previous,
            month_calls=month_calls,
            prompt_version=prompt_version,
            dry_run=dry_run,
            log=log,
        )
    except Exception as error:  # noqa: BLE001
        # 개요가 실패해도 월 요약은 이미 만들어졌다. 저장해두면 다음 실행이 개요만 다시 잡는다.
        log(f"  개요      실패 — 월 요약은 저장한다 ({type(error).__name__})")
        warnings.append(f"개요 종합 실패: {type(error).__name__}: {error}")
        overview = previous.overview if previous else TimelineOverview()
        turning_points = _stored_turning_points(previous)
        overview_calls = 0

    months = apply_turning_points(months, turning_points)

    dates = [event.date for event in events]
    state = TimelineState(
        schema_version=TIMELINE_SCHEMA_VERSION,
        category_id=category_id,
        category_label=category_label,
        axis_limit=axis_limit,
        date_from=min(dates) if dates else "",
        date_to=max(dates) if dates else "",
        generated_at=now.isoformat(timespec="seconds"),
        months=months,
        overview=overview,
        warnings=warnings,
    )

    if not dry_run:
        save_state(path, state)
        log(f"[{category_label}] 저장: {path}")

    return BuildResult(
        category_id=category_id,
        category_label=category_label,
        state=state,
        plans=plans,
        month_calls=month_calls,
        overview_calls=overview_calls,
        state_path=path,
    )


def _resolve_overview(
    *,
    provider,
    category_label: str,
    months: list[TimelineMonth],
    previous: TimelineState | None,
    month_calls: int,
    prompt_version: int,
    dry_run: bool,
    log: Callable[[str], None],
) -> tuple[TimelineOverview, list[TurningPointSelection], int]:
    """개요를 다시 만들지 정한다. 월 요약이 하나도 안 바뀌었으면 부르지 않는다."""
    digest = overview_input_hash(months, prompt_version=prompt_version)
    if previous is not None and month_calls == 0 and previous.overview.input_hash == digest:
        log("  개요      건너뜀 (unchanged)")
        return previous.overview, _stored_turning_points(previous), 0

    if not any(month.summary for month in months):
        # 아직 종합된 달이 하나도 없다. 요약할 재료가 없으니 부르지 않는다.
        return TimelineOverview(input_hash=digest), [], 0

    if dry_run:
        log("  개요      [dry-run] 종합 예정")
        return (
            previous.overview if previous else TimelineOverview(input_hash=digest),
            _stored_turning_points(previous),
            0,
        )

    log("  개요      종합")
    overview, selections = synthesize_overview(
        provider, category_label, months, prompt_version=prompt_version
    )
    return overview, selections, 1


def _stored_turning_points(previous: TimelineState | None) -> list[TurningPointSelection]:
    """개요 생성 실패나 무변경 실행에서는 기존 사건 단위 전환점을 보존한다."""
    if previous is None:
        return []
    return [
        TurningPointSelection(event_id=event.event_id, reason=event.turning_point_reason)
        for month in previous.months
        for event in month.axis_events
        if event.turning_point_reason
    ]
