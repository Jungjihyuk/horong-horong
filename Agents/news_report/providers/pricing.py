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
    """1M 토큰당 USD 단가."""

    input_usd_per_mtok: float
    output_usd_per_mtok: float
    cached_input_usd_per_mtok: float
    cache_write_usd_per_mtok: float


def load_pricing(model: str, path: str | None = None) -> ModelPricing | None:
    """모르는 모델이면 None. 값을 지어내느니 비용을 «모름» 으로 두는 편이 낫다."""
    try:
        with open(path or _PRICING_PATH, encoding="utf-8") as handle:
            table = json.load(handle).get("models", {})
    except (OSError, json.JSONDecodeError):
        return None
    entry = table.get(model)
    if not entry:
        return None
    return ModelPricing(
        input_usd_per_mtok=float(entry["input"]),
        output_usd_per_mtok=float(entry["output"]),
        cached_input_usd_per_mtok=float(entry.get("cached_input", entry["input"])),
        cache_write_usd_per_mtok=float(entry.get("cache_write", entry["input"])),
    )


def estimate_cost_usd(
    *,
    input_tokens: int,
    output_tokens: int,
    cached_input_tokens: int = 0,
    cache_write_input_tokens: int = 0,
    pricing: ModelPricing,
) -> float:
    """토큰 수 → USD. 캐시 읽기/쓰기는 단가가 달라 따로 곱한다."""
    return (
        input_tokens * pricing.input_usd_per_mtok
        + output_tokens * pricing.output_usd_per_mtok
        + cached_input_tokens * pricing.cached_input_usd_per_mtok
        + cache_write_input_tokens * pricing.cache_write_usd_per_mtok
    ) / 1_000_000
