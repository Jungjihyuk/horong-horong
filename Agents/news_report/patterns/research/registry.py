"""research pattern 이름을 실행 구현체로 변환한다."""

from __future__ import annotations

from collections.abc import Callable

from patterns.research.evidence_synthesis_v1 import EvidenceSynthesisV1Research
from patterns.research.protocols import ResearchPattern


ResearchPatternFactory = Callable[[], ResearchPattern]


_RESEARCH_PATTERN_FACTORIES: dict[str, ResearchPatternFactory] = {
    EvidenceSynthesisV1Research.name: EvidenceSynthesisV1Research,
}


def create_research_pattern(name: str) -> ResearchPattern:
    """research pattern 이름에 맞는 실행 구현체를 생성한다."""
    try:
        factory = _RESEARCH_PATTERN_FACTORIES[name]
    except KeyError as error:
        supported = ", ".join(sorted(_RESEARCH_PATTERN_FACTORIES))
        raise ValueError(
            f"지원하지 않는 research pattern: {name} (supported: {supported})"
        ) from error
    return factory()


def default_research_pattern_name() -> str:
    """뉴스 리포트 deep research의 기본 pattern 이름을 반환한다."""
    return EvidenceSynthesisV1Research.name
