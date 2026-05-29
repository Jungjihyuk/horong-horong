"""뉴스 source connector 구현체가 지켜야 하는 최소 계약."""

from typing import Protocol


class NewsConnector(Protocol):
    """외부 source에서 뉴스 항목을 수집하는 connector 계약."""

    def collect(self) -> list[dict]:
        """수집한 뉴스 항목 목록을 반환한다."""
