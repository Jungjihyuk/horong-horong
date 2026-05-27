"""provider 이름을 실제 TextProvider 구현체로 변환한다."""

from collections.abc import Callable

from providers.cli_providers import (
    AntigravityCliProvider,
    ClaudeCliProvider,
    CodexCliProvider,
    GeminiCliProvider,
    OpencodeCliProvider,
)
from providers.protocols import TextProvider


ProviderFactory = Callable[[], TextProvider]


_PROVIDER_FACTORIES: dict[str, ProviderFactory] = {
    "antigravity": AntigravityCliProvider,
    "claude": ClaudeCliProvider,
    "codex": CodexCliProvider,
    "gemini": GeminiCliProvider,
    "opencode": OpencodeCliProvider,
}


def create_provider(name: str) -> TextProvider:
    """provider 이름에 맞는 구현체를 생성한다.

    Args:
        name: 요청 JSON의 provider 이름.

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
    return factory()
