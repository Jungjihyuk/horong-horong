"""provider 호출의 토큰/비용 소모량과 요금제 한도 스냅샷 표현."""

from __future__ import annotations

from dataclasses import dataclass, replace


@dataclass(frozen=True)
class RateLimitSnapshot:
    """CLI가 보고한 요금제 한도 사용률 스냅샷.

    window_minutes는 요금제마다 다르다 (pro는 300/10080, free는 43200이고
    secondary가 없다). 따라서 '5시간'/'주간' 같은 라벨을 하드코딩하지 말고
    이 값에서 유도해야 한다.
    """

    scope: str
    used_percent: float | None = None
    window_minutes: int | None = None
    resets_at: int | None = None
    plan_type: str | None = None

    def to_payload(self) -> dict[str, object]:
        """trace JSONL용 snake_case 표현."""
        return {
            key: value
            for key, value in {
                "scope": self.scope,
                "used_percent": self.used_percent,
                "window_minutes": self.window_minutes,
                "resets_at": self.resets_at,
                "plan_type": self.plan_type,
            }.items()
            if value is not None
        }

    def to_result_payload(self) -> dict[str, object]:
        """Swift 앱이 읽는 result.json용 camelCase 표현."""
        return {
            "scope": self.scope,
            "usedPercent": self.used_percent,
            "windowMinutes": self.window_minutes,
            "resetsAt": self.resets_at,
            "planType": self.plan_type,
        }


@dataclass(frozen=True)
class UsageRecord:
    """provider 호출 1회(또는 누적)의 소모량.

    토큰과 비용은 합산 가능하지만 rate_limits는 시점 스냅샷이라 합산하지 않고
    가장 나중 값으로 대체한다.
    """

    input_tokens: int = 0
    output_tokens: int = 0
    cached_input_tokens: int = 0
    cache_write_input_tokens: int = 0
    reasoning_output_tokens: int = 0
    total_cost_usd: float | None = None
    # CLI 호출 횟수. 설정이 바뀌어도 재사용할 수 있도록 호출당 단가를 뽑는 데 쓴다.
    call_count: int = 0
    # 실행 중 관측한 가장 이른 사용률. 사용률은 누적 절대값이라 이것 없이는
    # "이번 실행으로 몇 % 썼는지"(rate_limits - rate_limits_first)를 알 수 없다.
    rate_limits_first: tuple[RateLimitSnapshot, ...] = ()
    # 실행 중 관측한 가장 마지막 사용률.
    rate_limits: tuple[RateLimitSnapshot, ...] = ()

    def merge(self, other: UsageRecord | None) -> UsageRecord:
        """다른 호출의 소모량을 누적한다."""
        if other is None:
            return self
        if self.total_cost_usd is None and other.total_cost_usd is None:
            cost = None
        else:
            cost = (self.total_cost_usd or 0.0) + (other.total_cost_usd or 0.0)
        return replace(
            self,
            input_tokens=self.input_tokens + other.input_tokens,
            output_tokens=self.output_tokens + other.output_tokens,
            cached_input_tokens=self.cached_input_tokens + other.cached_input_tokens,
            cache_write_input_tokens=(
                self.cache_write_input_tokens + other.cache_write_input_tokens
            ),
            reasoning_output_tokens=(
                self.reasoning_output_tokens + other.reasoning_output_tokens
            ),
            total_cost_usd=cost,
            call_count=self.call_count + other.call_count,
            # 가장 이른 관측을 유지한다.
            rate_limits_first=(
                self.rate_limits_first
                or self.rate_limits
                or other.rate_limits_first
                or other.rate_limits
            ),
            # 스냅샷이므로 최신 값으로 대체한다.
            rate_limits=other.rate_limits or self.rate_limits,
        )

    def to_result_payload(self) -> dict[str, object]:
        """Swift 앱이 읽는 result.json용 camelCase 표현."""
        return {
            "inputTokens": self.input_tokens,
            "outputTokens": self.output_tokens,
            "cachedInputTokens": self.cached_input_tokens,
            "cacheWriteInputTokens": self.cache_write_input_tokens,
            "reasoningOutputTokens": self.reasoning_output_tokens,
            "totalCostUSD": self.total_cost_usd,
            "callCount": self.call_count,
            "rateLimitsFirst": [
                limit.to_result_payload() for limit in self.rate_limits_first
            ],
            "rateLimits": [limit.to_result_payload() for limit in self.rate_limits],
        }

    def to_payload(self) -> dict[str, object]:
        """trace JSONL용 snake_case 표현."""
        payload: dict[str, object] = {
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "cached_input_tokens": self.cached_input_tokens,
            "cache_write_input_tokens": self.cache_write_input_tokens,
            "reasoning_output_tokens": self.reasoning_output_tokens,
            "call_count": self.call_count,
        }
        if self.total_cost_usd is not None:
            payload["total_cost_usd"] = self.total_cost_usd
        if self.rate_limits:
            payload["rate_limits"] = [limit.to_payload() for limit in self.rate_limits]
        return payload


def total_usage_of(provider: object) -> UsageRecord | None:
    """provider가 누적한 실행 전체 소모량을 읽는다.

    소모량을 보고하지 않는 provider(antigravity/opencode/hermes/ollama)는
    None을 돌려준다.
    """
    usage = getattr(provider, "_run_usage", None)
    return usage if isinstance(usage, UsageRecord) else None
