"""과금형 Anthropic provider 단위 테스트.

실제 API 는 부르지 않는다. client 를 주입해 계약과 «과금 사고 방지» 규칙만 검증한다.
"""

import pytest
from pydantic import BaseModel

from providers.anthropic_provider import AnthropicApiProvider
from providers.protocols import RateLimitError, StructuredProvider
from providers.usage import total_usage_of


class Answer(BaseModel):
    value: str


class FakeUsage:
    def __init__(self, input_tokens=1000, output_tokens=200):
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.cache_read_input_tokens = 0
        self.cache_creation_input_tokens = 0


class FakeMessages:
    def __init__(self, parsed=None, error=None):
        self._parsed = parsed
        self._error = error
        self.parse_calls = 0

    def parse(self, **kwargs):
        self.parse_calls += 1
        if self._error is not None:
            raise self._error
        response = type("Response", (), {})()
        response.parsed_output = self._parsed
        response.usage = FakeUsage()
        return response


class FakeClient:
    def __init__(self, parsed=None, error=None):
        self.messages = FakeMessages(parsed=parsed, error=error)


class FakeRateLimitError(Exception):
    """anthropic.RateLimitError 를 이름과 status_code 로만 흉내낸다."""

    status_code = 429


FakeRateLimitError.__name__ = "RateLimitError"


# 시나리오 1. 기존 provider 계약을 그대로 만족한다.
@pytest.mark.unit
def test_anthropic_provider__contract__satisfies_structured_provider():
    # Given/When: provider 를 만든다.
    provider = AnthropicApiProvider(client=FakeClient())

    # Then: 다른 provider 와 교체 가능하다.
    assert isinstance(provider, StructuredProvider)


# 시나리오 2. preflight 를 받지 않는다고 표시한다 (과금 사고 방지).
@pytest.mark.unit
def test_anthropic_provider__preflight_flag__is_false():
    # Given/When/Then: `/usage` 를 프롬프트로 보내면 그대로 청구되므로 막아야 한다.
    assert AnthropicApiProvider(client=FakeClient()).supports_slash_preflight is False


# 시나리오 3. 구조화 응답과 함께 소모량·비용이 기록된다.
@pytest.mark.unit
def test_anthropic_provider__generate_json__records_usage_and_cost():
    # Given: 유효한 응답을 주는 client.
    provider = AnthropicApiProvider(model="claude-opus-5", client=FakeClient(parsed=Answer(value="ok")))

    # When: 구조화 응답을 두 번 받는다.
    provider.generate_json("프롬프트", Answer)
    provider.generate_json("프롬프트", Answer)

    # Then: 누적 소모량이 tracing/result 경로가 읽는 이름으로 남는다.
    usage = total_usage_of(provider)
    assert usage.call_count == 2
    assert usage.input_tokens == 2000
    # 1M당 $5/$25 → (1000*5 + 200*25)/1e6 = $0.01, 두 번이면 $0.02
    assert usage.total_cost_usd == pytest.approx(0.02)


# 시나리오 4. 모르는 모델이면 비용을 지어내지 않는다.
@pytest.mark.unit
def test_anthropic_provider__unknown_model__leaves_cost_none():
    # Given: 단가표에 없는 모델.
    provider = AnthropicApiProvider(model="mystery-model", client=FakeClient(parsed=Answer(value="ok")))

    # When: 호출한다.
    provider.generate_json("프롬프트", Answer)

    # Then: 토큰은 세지만 비용은 «모름» 으로 둔다.
    assert provider._last_usage.input_tokens == 1000
    assert provider._last_usage.total_cost_usd is None


# 시나리오 5. 429 는 파이프라인이 이미 아는 RateLimitError 로 번역된다.
@pytest.mark.unit
def test_anthropic_provider__rate_limited__raises_pipeline_rate_limit_error():
    # Given: 429 를 던지는 client.
    provider = AnthropicApiProvider(client=FakeClient(error=FakeRateLimitError("429")))

    # When/Then: ontology/research 단계가 잡는 예외 타입으로 올라온다.
    with pytest.raises(RateLimitError):
        provider.generate_json("프롬프트", Answer)


# 시나리오 6. 키가 없으면 실제 호출 시점에 분명한 메시지로 막는다.
@pytest.mark.unit
def test_anthropic_provider__missing_api_key__raises_with_guidance():
    # Given: client 주입도 키도 없다.
    provider = AnthropicApiProvider(api_key=None)

    # When/Then: 어디에 키를 넣어야 하는지 알려준다.
    with pytest.raises((ValueError, RuntimeError), match="ANTHROPIC_API_KEY|anthropic SDK"):
        provider.generate_json("프롬프트", Answer)


# 시나리오 7. tracing 래퍼가 preflight 표식을 가리지 않는다.
@pytest.mark.unit
def test_traced_provider__wrapping_metered_provider__preserves_preflight_flag():
    # Given: 과금형 provider 를 tracing 래퍼로 감쌌다.
    from providers.traced_provider import TracedStructuredProvider

    wrapped = TracedStructuredProvider(
        AnthropicApiProvider(client=FakeClient()), provider_name="anthropic", trace=None
    )

    # Then: 래퍼 너머로도 «preflight 하지 마라» 가 보인다.
    # 이 값이 가려지면 리포트 실행마다 쓰레기 호출 하나가 그대로 청구된다.
    assert wrapped.supports_slash_preflight is False


# 시나리오 8. 구독 CLI provider 는 여전히 preflight 를 받는다.
@pytest.mark.unit
def test_traced_provider__wrapping_cli_provider__still_allows_preflight():
    # Given: 표식이 없는 기존 provider.
    from providers.traced_provider import TracedStructuredProvider

    class LegacyProvider:
        def run(self, prompt):
            return ""

        def generate_text(self, prompt, options=None):
            return ""

        def generate_json(self, prompt, schema_model, options=None):
            return schema_model()

    wrapped = TracedStructuredProvider(
        LegacyProvider(), provider_name="claude", trace=None
    )

    # Then: 기본값 True 라 기존 동작이 그대로다.
    assert wrapped.supports_slash_preflight is True


# 시나리오 9. factory 가 이름으로 과금형 provider 를 만든다.
@pytest.mark.unit
def test_create_provider__anthropic__returns_configured_metered_provider():
    # Given: 요청이 지정할 수 있는 provider 이름.
    from contracts.news_job_request import ProviderOptionsConfig
    from providers.factory import create_provider

    # When: 모델과 timeout 을 주어 만든다.
    provider = create_provider(
        "anthropic", ProviderOptionsConfig(model="claude-sonnet-5", timeout=42)
    )

    # Then: 옵션이 반영되고 계약을 만족한다.
    assert isinstance(provider, AnthropicApiProvider)
    assert provider.model == "claude-sonnet-5"
    assert provider.timeout == 42
