"""Text provider factory 단위 테스트."""

import pytest

from contracts.news_job_request import ProviderOptionsConfig
from providers.cli_providers import CodexCliProvider
from providers.factory import create_provider
from providers.ollama_provider import OllamaProvider
from providers.protocols import StructuredProvider


# 시나리오 1. 등록된 provider 이름은 해당 TextProvider 구현체로 변환된다.
@pytest.mark.unit
def test_create_provider__codex__returns_codex_cli_provider():
    # Given: 요청 JSON에서 전달된 codex provider 이름을 준비한다.
    provider_name = "codex"

    # When: factory가 provider 이름을 구현체로 변환한다.
    provider = create_provider(provider_name)

    # Then: codex CLI provider 구현체가 반환된다.
    assert isinstance(provider, CodexCliProvider)
    assert isinstance(provider, StructuredProvider)


# 시나리오 2. 등록되지 않은 provider 이름은 runner 실행 전에 명확히 거부된다.
@pytest.mark.unit
def test_create_provider__unknown_provider__raises_value_error():
    # Given: registry에 없는 provider 이름을 준비한다.
    provider_name = "unknown-provider"

    # When / Then: factory가 지원하지 않는 provider 오류를 발생시킨다.
    with pytest.raises(ValueError, match="지원하지 않는 provider"):
        _ = create_provider(provider_name)


# 시나리오 3. ollama provider 이름은 로컬 structured provider 구현체로 변환된다.
@pytest.mark.unit
def test_create_provider__ollama__returns_ollama_provider():
    # Given: 요청 JSON에서 전달된 ollama provider 이름을 준비한다.
    provider_name = "ollama"

    # When: factory가 provider 이름을 구현체로 변환한다.
    provider = create_provider(provider_name)

    # Then: Ollama provider 구현체가 반환된다.
    assert isinstance(provider, OllamaProvider)


# 시나리오 4. ollama providerOptions는 OllamaProvider 생성 인자로 반영된다.
@pytest.mark.unit
def test_create_provider__ollama_options__configures_ollama_provider():
    # Given: 요청 JSON에서 검증된 ollama provider option을 준비한다.
    options = ProviderOptionsConfig(
        model="qwen3:32b",
        endpoint="http://localhost:11435",
        timeout=180.0,
    )

    # When: factory가 ollama provider를 생성한다.
    provider = create_provider("ollama", options)

    # Then: OllamaProvider 인스턴스에 모델/endpoint/timeout이 반영된다.
    assert isinstance(provider, OllamaProvider)
    assert provider.model == "qwen3:32b"
    assert provider.endpoint == "http://localhost:11435"
    assert provider.timeout == 180.0


# 시나리오 5. CLI provider는 providerOptions가 있어도 기존 구현체를 그대로 생성한다.
@pytest.mark.unit
def test_create_provider__cli_options__ignores_provider_options():
    # Given: CLI provider에는 아직 사용하지 않는 provider option을 준비한다.
    options = ProviderOptionsConfig(model="ignored-model")

    # When: factory가 codex provider를 생성한다.
    provider = create_provider("codex", options)

    # Then: 기존 codex CLI provider 구현체가 반환된다.
    assert isinstance(provider, CodexCliProvider)
