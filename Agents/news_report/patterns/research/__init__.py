"""조사와 추론 방법론 단위 research pattern 패키지.

수집/정규화된 자료를 `research_artifact` 계약에 맞는 중간 산출물로 변환한다.
"""

from patterns.research.context import ResearchContext
from patterns.research.registry import (
    create_research_pattern,
    default_research_pattern_name,
)
from patterns.research.result import ResearchResult

__all__ = [
    "ResearchContext",
    "ResearchResult",
    "create_research_pattern",
    "default_research_pattern_name",
]
