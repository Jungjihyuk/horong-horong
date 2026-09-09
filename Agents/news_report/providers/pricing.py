"""과금형 provider 의 토큰 사용량을 달러로 환산한다.

구독 CLI(`claude`, `codex`)는 `total_cost_usd` 를 직접 보고하지만 API 는 토큰 수만
준다. 그래서 여기서 단가를 곱한다. 단가는 `config/model_pricing.json` 에 데이터로
두었다 — 요금이 바뀌는 것은 코드 변경이 아니어야 한다.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass

_PRICING_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config", "model_pricing.json")


@dataclass(frozen=True)
class ModelPricing:
    """1M 토큰당 USD 단가. Google 스토리지만 1M 토큰·시간 기준이다."""

    input_usd_per_mtok: float
    output_usd_per_mtok: float
    cache_hit_usd_per_mtok: float
    cache_write_usd_per_mtok: float | None = None
    cache_storage_5m_usd_per_mtok: float | None = None
    cache_storage_1h_usd_per_mtok: float | None = None
    cache_storage_usd_per_mtok_hour: float | None = None


def load_pricing(
    model: str,
    path: str | None = None,
    *,
    prompt_tokens: int | None = None,
) -> ModelPricing | None:
    """모델과 호출별 프롬프트 크기에 맞는 단가를 읽는다."""
    try:
        with open(path or _PRICING_PATH, encoding="utf-8") as handle:
            table = json.load(handle).get("models", {})
    except (OSError, json.JSONDecodeError):
        return None
    entry = table.get(model)
    if not entry:
        return None
    tiers = entry.get("pricing_tiers")
    if tiers is not None:
        if prompt_tokens is None or not isinstance(tiers, list):
            # 구간 모델은 프롬프트 크기 없이 낮은 단가를 임의로 적용하면 안 된다.
            return None
        tier = next(
            (
                candidate
                for candidate in tiers
                if isinstance(candidate, dict)
                and prompt_tokens >= int(candidate.get("prompt_tokens_min", 0))
                and (
                    candidate.get("prompt_tokens_max") is None
                    or prompt_tokens <= int(candidate["prompt_tokens_max"])
                )
            ),
            None,
        )
        if tier is None:
            return None
        entry = {**entry, **tier}
    try:
        return ModelPricing(
            input_usd_per_mtok=float(entry["input"]),
            output_usd_per_mtok=float(entry["output"]),
            cache_hit_usd_per_mtok=float(entry["cache_hit"]),
            cache_write_usd_per_mtok=_optional_float(entry.get("cache_write")),
            cache_storage_5m_usd_per_mtok=_optional_float(
                entry.get("cache_storage_5m_ttl_usd_per_mtok")
            ),
            cache_storage_1h_usd_per_mtok=_optional_float(
                entry.get("cache_storage_1h_ttl_usd_per_mtok")
            ),
            cache_storage_usd_per_mtok_hour=_optional_float(
                entry.get("cache_storage_usd_per_mtok_hour")
            ),
        )
    except (KeyError, TypeError, ValueError):
        return None


def estimate_cost_usd(
    *,
    input_tokens: int,
    output_tokens: int,
    cache_hit_tokens: int = 0,
    cache_write_tokens: int = 0,
    cache_storage_5m_tokens: int = 0,
    cache_storage_1h_tokens: int = 0,
    cache_storage_token_hours: float = 0,
    pricing: ModelPricing,
) -> float:
    """토큰 수 → USD. 공급자별 캐시 쓰기·스토리지 과금을 따로 적용한다."""
    return (
        input_tokens * pricing.input_usd_per_mtok
        + output_tokens * pricing.output_usd_per_mtok
        + cache_hit_tokens * pricing.cache_hit_usd_per_mtok
        + cache_write_tokens * (pricing.cache_write_usd_per_mtok or 0)
        + cache_storage_5m_tokens * (pricing.cache_storage_5m_usd_per_mtok or 0)
        + cache_storage_1h_tokens * (pricing.cache_storage_1h_usd_per_mtok or 0)
        + cache_storage_token_hours
        * (pricing.cache_storage_usd_per_mtok_hour or 0)
    ) / 1_000_000


def _optional_float(value: object) -> float | None:
    return None if value is None else float(value)
