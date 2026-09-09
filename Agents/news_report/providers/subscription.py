"""AI CLI 구독 요금제의 세션 한도 소모율 환산.

구독 CLI(claude, codex, agy)는 비대화 모드에서 한도 잔여율을 제공하지 않거나
(claude, agy) 토큰만 제공한다. 이 모듈은 config/subscription_plans.json 에 정의된
5시간 세션 환산 기준표를 기반으로, 소모된 비용/토큰을 5시간 창 소모율(%) 스냅샷으로 변환한다.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, replace

from providers.usage import RateLimitSnapshot, UsageRecord

_SUBSCRIPTION_PATH = os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "config", "subscription_plans.json"
)


@dataclass(frozen=True)
class SubscriptionPlan:
    """구독 요금제의 5시간 세션 한도 환산 기준."""

    provider: str
    plan_type: str
    window_minutes: int
    tokens_per_percent: int | None = None
    cost_usd_per_percent: float | None = None
    description: str | None = None


def load_subscription_plan(
    provider: str, path: str | None = None
) -> SubscriptionPlan | None:
    """provider에 해당하는 구독 요금제 환산 기준을 읽는다."""
    try:
        with open(path or _SUBSCRIPTION_PATH, encoding="utf-8") as handle:
            plans = json.load(handle).get("plans", {})
    except (OSError, json.JSONDecodeError):
        return None

    entry = plans.get(provider)
    if not isinstance(entry, dict):
        return None

    try:
        return SubscriptionPlan(
            provider=provider,
            plan_type=str(entry["plan_type"]),
            window_minutes=int(entry.get("window_minutes", 300)),
            tokens_per_percent=_optional_int(entry.get("tokens_per_percent")),
            cost_usd_per_percent=_optional_float(entry.get("cost_usd_per_percent")),
            description=entry.get("description"),
        )
    except (KeyError, TypeError, ValueError):
        return None


def calculate_used_percent(
    usage: UsageRecord, plan: SubscriptionPlan
) -> float | None:
    """소모량(비용 또는 토큰)으로부터 5시간 세션 기준 소모율(%)을 계산한다."""
    # 비용이 있고 요율 기준이 있으면 비용 우선 (claude 등)
    if plan.cost_usd_per_percent is not None and plan.cost_usd_per_percent > 0:
        if usage.total_cost_usd is not None:
            return round(usage.total_cost_usd / plan.cost_usd_per_percent, 4)

    # 토큰 기준 환산
    if plan.tokens_per_percent is not None and plan.tokens_per_percent > 0:
        total_tokens = (
            usage.input_tokens
            + usage.output_tokens
            + usage.cache_hit_tokens
            + usage.cache_write_tokens
        )
        return round(total_tokens / plan.tokens_per_percent, 4)

    return None


def enrich_usage_with_subscription(
    usage: UsageRecord | None,
    provider: str,
    path: str | None = None,
) -> UsageRecord | None:
    """UsageRecord에 요금제 환산 스냅샷을 주입한다.

    CLI 자체에서 실측된 유의미한 사용률 변화(delta > 0)가 이미 존재하는 경우
    실측치를 그대로 보존하며, 없는 경우에만 subscription_plans.json 기준으로 주입한다.
    """
    if usage is None:
        return None

    # 이미 실측 delta가 있는지 확인
    if _has_measured_delta(usage):
        return usage

    plan = load_subscription_plan(provider, path=path)
    if plan is None:
        return usage

    delta_percent = calculate_used_percent(usage, plan)
    if delta_percent is None:
        return usage

    snapshot_first = RateLimitSnapshot(
        scope="primary",
        used_percent=0.0,
        window_minutes=plan.window_minutes,
        plan_type=plan.plan_type,
    )
    snapshot_last = RateLimitSnapshot(
        scope="primary",
        used_percent=delta_percent,
        window_minutes=plan.window_minutes,
        plan_type=plan.plan_type,
    )

    return replace(
        usage,
        rate_limits_first=(snapshot_first,),
        rate_limits=(snapshot_last,),
    )


def _has_measured_delta(usage: UsageRecord) -> bool:
    """이미 실측된 유효한 사용률 차감이 존재하는지 확인한다."""
    first = next((s for s in usage.rate_limits_first if s.scope == "primary"), None)
    last = next((s for s in usage.rate_limits if s.scope == "primary"), None)
    if (
        first is not None
        and last is not None
        and first.used_percent is not None
        and last.used_percent is not None
    ):
        return (last.used_percent - first.used_percent) > 0
    return False


def _optional_int(value: object) -> int | None:
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _optional_float(value: object) -> float | None:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None
