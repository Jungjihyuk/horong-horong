"""provider 이름을 실제 TextProvider 구현체로 변환한다."""

from collections.abc import Callable

from contracts.news_job_request import ProviderOptionsConfig
from providers.cli_providers import (
    AntigravityCliProvider,
    ClaudeCliProvider,
    CodexCliProvider,
    GeminiCliProvider,
    OpencodeCliProvider,
)
from providers.ollama_provider import OllamaProvider
from providers.protocols import TextProvider


ProviderFactory = Callable[[], TextProvider]


_PROVIDER_FACTORIES: dict[str, ProviderFactory] = {
    "antigravity": AntigravityCliProvider,
    "claude": ClaudeCliProvider,
    "codex": CodexCliProvider,
    "gemini": GeminiCliProvider,
    "ollama": OllamaProvider,
    "opencode": OpencodeCliProvider,
}


def create_provider(
    name: str,
    options: ProviderOptionsConfig | None = None,
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
        return create_ollama_provider(options)
    provider = factory()
    if options and options.timeout:
        provider.timeout = options.timeout
    return provider


def create_ollama_provider(options: ProviderOptionsConfig | None) -> OllamaProvider:
    """request providerOptions를 OllamaProvider 생성 인자로 변환한다."""
    if options is None:
        return OllamaProvider()

    return OllamaProvider(
        model=options.model or "qwen3:14b",
        endpoint=options.endpoint or "http://localhost:11434",
        timeout=options.timeout or 120,
    )
