"""뉴스 source type을 실제 connector 구현체로 변환한다."""

from __future__ import annotations

from collections.abc import Callable

from connectors.google_connector import GoogleConnector
from connectors.linkedin_connector import LinkedInConnector
from connectors.protocols import NewsConnector
from connectors.youtube_connector import YouTubeConnector
from connectors.yozm_connector import YozmConnector


ConnectorFactory = Callable[[dict, int], NewsConnector]


_CONNECTOR_FACTORIES: dict[str, ConnectorFactory] = {
    "google_news": GoogleConnector,
    "linkedin": LinkedInConnector,
    "youtube": YouTubeConnector,
    "yozm_it": YozmConnector,
}


def supported_source_types() -> set[str]:
    """현재 등록된 뉴스 source type 목록을 반환한다."""
    return set(_CONNECTOR_FACTORIES)


def is_supported_source(source_type: str) -> bool:
    """source type이 등록된 connector를 갖고 있는지 확인한다."""
    return source_type in _CONNECTOR_FACTORIES


def create_connector(source: dict, max_items: int) -> NewsConnector:
    """source 설정에 맞는 connector 구현체를 생성한다.

    Args:
        source: 요청 JSON의 source 설정 dict.
        max_items: 이 source에서 수집할 최대 항목 수.

    Returns:
        `collect() -> list[dict]` 계약을 만족하는 connector 구현체.

    Raises:
        ValueError: 등록되지 않은 source type일 때.
    """
    source_type = source.get("type", "")
    try:
        factory = _CONNECTOR_FACTORIES[source_type]
    except KeyError as error:
        supported = ", ".join(sorted(_CONNECTOR_FACTORIES))
        raise ValueError(
            f"지원하지 않는 source type: {source_type} (supported: {supported})"
        ) from error
    return factory(source, max_items)
