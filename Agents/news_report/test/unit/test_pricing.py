"""모델별 토큰 단가 스키마와 비용 계산 테스트."""

import json

import pytest

from providers.pricing import estimate_cost_usd, load_pricing


@pytest.mark.unit
def test_load_pricing__cache_fields__use_hit_and_ttl_storage_terms(tmp_path):
    pricing_path = tmp_path / "pricing.json"
    pricing_path.write_text(
        json.dumps(
            {
                "models": {
                    "model": {
                        "input": 10,
                        "cache_storage_5m_ttl_usd_per_mtok": 12.5,
                        "cache_storage_1h_ttl_usd_per_mtok": 20,
                        "cache_hit": 0.25,
                        "output": 50,
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    pricing = load_pricing("model", path=str(pricing_path))

    assert pricing is not None
    assert pricing.cache_hit_usd_per_mtok == 0.25
    assert pricing.cache_storage_5m_usd_per_mtok == 12.5
    assert pricing.cache_storage_1h_usd_per_mtok == 20


@pytest.mark.unit
def test_estimate_cost__cache_storage__prices_each_ttl_separately():
    pricing = load_pricing("claude-fable-5-1")
    assert pricing is not None

    cost = estimate_cost_usd(
        input_tokens=1_000_000,
        output_tokens=1_000_000,
        cache_hit_tokens=1_000_000,
        cache_storage_5m_tokens=1_000_000,
        cache_storage_1h_tokens=1_000_000,
        pricing=pricing,
    )

    assert cost == pytest.approx(92.75)


@pytest.mark.unit
@pytest.mark.parametrize(
    ("prompt_tokens", "input_price", "output_price", "cache_hit_price"),
    [
        (200_000, 2.0, 12.0, 0.20),
        (200_001, 4.0, 18.0, 0.40),
    ],
)
def test_load_pricing__tiered_model__selects_rate_by_prompt_size(
    prompt_tokens, input_price, output_price, cache_hit_price
):
    pricing = load_pricing("gemini-3.1-pro-preview", prompt_tokens=prompt_tokens)

    assert pricing is not None
    assert pricing.input_usd_per_mtok == input_price
    assert pricing.output_usd_per_mtok == output_price
    assert pricing.cache_hit_usd_per_mtok == cache_hit_price
    assert pricing.cache_storage_usd_per_mtok_hour == 4.50


@pytest.mark.unit
def test_load_pricing__tiered_model_without_prompt_size__does_not_guess():
    assert load_pricing("gemini-3.1-pro-preview") is None


@pytest.mark.unit
@pytest.mark.parametrize(
    ("prompt_tokens", "input_price", "output_price", "cache_hit_price", "cache_write_price"),
    [
        (272_000, 4.0, 20.0, 0.4, 5.0),
        (272_001, 8.0, 30.0, 0.8, 10.0),
    ],
)
def test_load_pricing__gpt_tier__includes_cache_write_rate(
    prompt_tokens, input_price, output_price, cache_hit_price, cache_write_price
):
    pricing = load_pricing("gpt-5.6-sol", prompt_tokens=prompt_tokens)

    assert pricing is not None
    assert pricing.input_usd_per_mtok == input_price
    assert pricing.output_usd_per_mtok == output_price
    assert pricing.cache_hit_usd_per_mtok == cache_hit_price
    assert pricing.cache_write_usd_per_mtok == cache_write_price


@pytest.mark.unit
def test_estimate_cost__openai_cache_write__is_billed_separately():
    pricing = load_pricing("gpt-5.6-sol", prompt_tokens=272_000)
    assert pricing is not None

    cost = estimate_cost_usd(
        input_tokens=1_000_000,
        output_tokens=1_000_000,
        cache_hit_tokens=1_000_000,
        cache_write_tokens=1_000_000,
        pricing=pricing,
    )

    assert cost == pytest.approx(29.4)
