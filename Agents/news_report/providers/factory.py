"""provider 이름을 실제 TextProvider 구현체로 변환한다."""

from collections.abc import Callable

from contracts.news_job_request import ProviderOptionsConfig
from providers.cli_providers import (
    AntigravityCliProvider,
    ClaudeCliProvider,
    CodexCliProvider,
    OpencodeCliProvider,
    HermesCliProvider,
)
from providers.anthropic_provider import DEFAULT_MODEL, AnthropicApiProvider
from providers.ollama_provider import OllamaProvider
from providers.protocols import TextProvider


ProviderFactory = Callable[[], TextProvider]


_PROVIDER_FACTORIES: dict[str, ProviderFactory] = {
    "anthropic": AnthropicApiProvider,
    "antigravity": AntigravityCliProvider,
    "claude": ClaudeCliProvider,
    "codex": CodexCliProvider,
    "ollama": OllamaProvider,
    "opencode": OpencodeCliProvider,
    "hermes": HermesCliProvider,
}


def create_provider(
    name: str,
    options: ProviderOptionsConfig | None = None,
    *,
    think: bool | None = None,
) -> TextProvider:
    """provider 이름에 맞는 구현체를 생성한다.

    Args:
        name: 요청 JSON의 provider 이름.
        options: provider별 선택 옵션. ollama는 model/endpoint/timeout,
            CLI provider는 timeout만 사용한다.

    Returns:
        `run(prompt) -> str` 계약을 만족하는 provider 구현체.

    Raises:
        ValueError: 등록되지 않은 provider 이름일 때.
    """
    try:
        factory = _PROVIDER_FACTORIES[name]
    except KeyError as error:
        supported = ", ".join(sorted(_PROVIDER_FACTORIES))
        raise ValueError(f"지원하지 않는 provider: {name} (supported: {supported})") from error
    if name == "ollama":
        return create_ollama_provider(options, think=think)
    if name == "anthropic":
        return create_anthropic_provider(options)
    provider = factory()
    if options and options.timeout:
        provider.timeout = options.timeout
    return provider


def create_anthropic_provider(
    options: ProviderOptionsConfig | None,
) -> AnthropicApiProvider:
    """과금형 Anthropic provider 를 만든다.

    키는 여기서 찾는다(환경변수 → .env). 생성 시점에 없어도 예외를 던지지 않는 이유는
    dry-run 처럼 실제로 부르지 않는 경로가 있기 때문이다 — 실제 호출 시점에 막는다.
    """
    from providers.env import resolve_api_key

    return AnthropicApiProvider(
        model=(options.model if options and options.model else DEFAULT_MODEL),
        api_key=resolve_api_key(),
        timeout=(options.timeout if options and options.timeout else 120.0),
    )


def create_ollama_provider(
    options: ProviderOptionsConfig | None,
    *,
    think: bool | None = None,
) -> OllamaProvider:
    """request providerOptions를 OllamaProvider 생성 인자로 변환한다."""
    if options is None:
        return OllamaProvider(think=think)

    return OllamaProvider(
        think=think,
        model=options.model or "qwen3:14b",
        endpoint=options.endpoint or "http://localhost:11434",
        timeout=options.timeout or 120,
    )
