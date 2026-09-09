"""구독 요금제 환산(subscription_plans.json) 단위 테스트."""

import pytest

from providers.subscription import (
    SubscriptionPlan,
    calculate_used_percent,
    enrich_usage_with_subscription,
    load_subscription_plan,
)
from providers.usage import RateLimitSnapshot, UsageRecord


@pytest.mark.unit
def test_load_subscription_plan__valid_providers__returns_plan():
    # Given / When: config/subscription_plans.json 에서 정의된 provider들을 읽는다.
    claude = load_subscription_plan("claude")
    codex = load_subscription_plan("codex")
    antigravity = load_subscription_plan("antigravity")

    # Then: 각 요금제 정보가 명세대로 로드된다.
    assert claude is not None
    assert claude.plan_type == "Claude Pro"
    assert claude.window_minutes == 300
    assert claude.cost_usd_per_percent == 0.1
    assert claude.tokens_per_percent == 15000

    assert codex is not None
    assert codex.plan_type == "ChatGPT Plus"
    assert codex.window_minutes == 300
    assert codex.tokens_per_percent == 250000

    assert antigravity is not None
    assert antigravity.plan_type == "Google AI Pro"
    assert antigravity.window_minutes == 300
    assert antigravity.tokens_per_percent == 500000


@pytest.mark.unit
def test_load_subscription_plan__unknown_provider__returns_none():
    assert load_subscription_plan("nonexistent_llm") is None


@pytest.mark.unit
def test_calculate_used_percent__claude_with_cost__calculates_accurately():
    # Given: Claude Pro 플랜과 $0.20 비용이 기록된 usage
    plan = load_subscription_plan("claude")
    assert plan is not None
    usage = UsageRecord(input_tokens=1000, output_tokens=500, total_cost_usd=0.20)

    # When: 소모율을 계산한다.
    percent = calculate_used_percent(usage, plan)

    # Then: $0.20 소모 시 2.0% ($0.10 당 1%)
    assert percent == 2.0


@pytest.mark.unit
def test_calculate_used_percent__claude_without_cost_fallback_to_tokens():
    # Given: Claude Pro 플랜과 비용 없이 30,000 토큰만 기록된 usage
    plan = load_subscription_plan("claude")
    assert plan is not None
    usage = UsageRecord(
        input_tokens=20000, output_tokens=5000, cache_hit_tokens=5000, total_cost_usd=None
    )

    # When: 소모율을 계산한다.
    percent = calculate_used_percent(usage, plan)

    # Then: 30,000 토큰 소모 시 2.0% (15,000 토큰 당 1%)
    assert percent == 2.0


@pytest.mark.unit
def test_calculate_used_percent__codex_tokens__calculates_accurately():
    # Given: ChatGPT Plus 플랜과 500,000 토큰 사용량
    plan = load_subscription_plan("codex")
    assert plan is not None
    usage = UsageRecord(input_tokens=400000, output_tokens=100000)

    # When: 소모율을 계산한다.
    percent = calculate_used_percent(usage, plan)

    # Then: 50만 토큰 소모 시 2.0% (25만 토큰 당 1%)
    assert percent == 2.0


@pytest.mark.unit
def test_calculate_used_percent__antigravity_tokens__calculates_accurately():
    # Given: Google AI Pro 플랜과 100만 토큰 및 6,000 토큰 사용량
    plan = load_subscription_plan("antigravity")
    assert plan is not None

    usage_1m = UsageRecord(input_tokens=800000, output_tokens=200000)
    assert calculate_used_percent(usage_1m, plan) == 2.0

    usage_6k = UsageRecord(input_tokens=5000, output_tokens=1000)
    # 6,000 / 500,000 = 0.012%
    assert calculate_used_percent(usage_6k, plan) == 0.012


@pytest.mark.unit
def test_enrich_usage_with_subscription__none_usage__returns_none():
    assert enrich_usage_with_subscription(None, "claude") is None


@pytest.mark.unit
def test_enrich_usage_with_subscription__already_has_measured_delta__preserves_values():
    # Given: 이미 CLI rollout 등에서 실측된 사용률 차감(2.0% -> 5.0%)이 존재하는 usage
    original_first = (
        RateLimitSnapshot(scope="primary", used_percent=2.0, window_minutes=300, plan_type="pro"),
    )
    original_last = (
        RateLimitSnapshot(scope="primary", used_percent=5.0, window_minutes=300, plan_type="pro"),
    )
    usage = UsageRecord(
        input_tokens=50000,
        rate_limits_first=original_first,
        rate_limits=original_last,
    )

    # When: enrich를 수행한다.
    enriched = enrich_usage_with_subscription(usage, "codex")

    # Then: 실측치(delta 3.0%)를 덮어쓰지 않고 그대로 유지한다.
    assert enriched is not None
    assert enriched.rate_limits_first == original_first
    assert enriched.rate_limits == original_last


@pytest.mark.unit
def test_enrich_usage_with_subscription__no_rate_limits__injects_subscription_snapshots():
    # Given: rate limits 가 비어 있는 antigravity 6,000 토큰 사용량
    usage = UsageRecord(input_tokens=5000, output_tokens=1000, total_cost_usd=0.0075)

    # When: antigravity 요금제로 enrich 한다.
    enriched = enrich_usage_with_subscription(usage, "antigravity")

    # Then: 0.0 -> 0.012% 스냅샷이 생성되어 주입된다.
    assert enriched is not None
    assert len(enriched.rate_limits_first) == 1
    assert len(enriched.rate_limits) == 1

    first = enriched.rate_limits_first[0]
    last = enriched.rate_limits[0]

    assert first.scope == "primary"
    assert first.used_percent == 0.0
    assert first.window_minutes == 300
    assert first.plan_type == "Google AI Pro"

    assert last.scope == "primary"
    assert last.used_percent == 0.012
    assert last.window_minutes == 300
    assert last.plan_type == "Google AI Pro"
