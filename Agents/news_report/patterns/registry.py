"""pattern 이름을 실행 구현체로 변환한다."""

from __future__ import annotations

from collections.abc import Callable

from patterns.pipelines.news_report_v1 import NewsReportV1Pipeline
from patterns.protocols import PipelinePattern


PatternFactory = Callable[[], PipelinePattern]


_PATTERN_FACTORIES: dict[str, PatternFactory] = {
    NewsReportV1Pipeline.name: NewsReportV1Pipeline,
}


def create_pattern(name: str) -> PipelinePattern:
    """pattern 이름에 맞는 실행 구현체를 생성한다."""
    try:
        factory = _PATTERN_FACTORIES[name]
    except KeyError as error:
        supported = ", ".join(sorted(_PATTERN_FACTORIES))
        raise ValueError(f"지원하지 않는 pattern: {name} (supported: {supported})") from error
    return factory()


def default_pattern_name() -> str:
    """뉴스 리포트 runner의 기본 pattern 이름을 반환한다."""
    return NewsReportV1Pipeline.name
