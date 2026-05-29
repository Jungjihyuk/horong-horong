"""뉴스 connector registry 단위 테스트."""

import pytest

from connectors.registry import create_connector
from connectors.youtube_connector import YouTubeConnector


# 시나리오 1. 등록된 source type은 해당 뉴스 connector 구현체로 변환된다.
@pytest.mark.unit
def test_create_connector__youtube_source__returns_youtube_connector():
    # Given: YouTube source 설정과 최대 수집 개수를 준비한다.
    source = {"type": "youtube", "enabled": True, "channelId": "channel-1"}

    # When: registry가 source type을 connector 구현체로 변환한다.
    connector = create_connector(source, max_items=5)

    # Then: YouTube connector 구현체가 반환된다.
    assert isinstance(connector, YouTubeConnector)


# 시나리오 2. 등록되지 않은 source type은 connector 생성 단계에서 명확히 거부된다.
@pytest.mark.unit
def test_create_connector__unknown_source_type__raises_value_error():
    # Given: registry에 없는 source type 설정을 준비한다.
    source = {"type": "rss", "enabled": True}

    # When / Then: registry가 지원하지 않는 source type 오류를 발생시킨다.
    with pytest.raises(ValueError, match="지원하지 않는 source type"):
        create_connector(source, max_items=5)
