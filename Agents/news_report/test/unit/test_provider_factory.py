"""Text provider factory 단위 테스트."""

import pytest

from providers.cli_providers import CodexCliProvider
from providers.factory import create_provider


# 시나리오 1. 등록된 provider 이름은 해당 TextProvider 구현체로 변환된다.
@pytest.mark.unit
def test_create_provider__codex__returns_codex_cli_provider():
    # Given: 요청 JSON에서 전달된 codex provider 이름을 준비한다.
    provider_name = "codex"

    # When: factory가 provider 이름을 구현체로 변환한다.
    provider = create_provider(provider_name)

    # Then: codex CLI provider 구현체가 반환된다.
    assert isinstance(provider, CodexCliProvider)


# 시나리오 2. 등록되지 않은 provider 이름은 runner 실행 전에 명확히 거부된다.
@pytest.mark.unit
def test_create_provider__unknown_provider__raises_value_error():
    # Given: registry에 없는 provider 이름을 준비한다.
    provider_name = "unknown-provider"

    # When / Then: factory가 지원하지 않는 provider 오류를 발생시킨다.
    with pytest.raises(ValueError, match="지원하지 않는 provider"):
        create_provider(provider_name)
