"""research 방법론을 실행 가능한 pipeline 흐름으로 조립하는 pattern 패키지.

baseline 뉴스 리포트 흐름부터 multi-pass, local model, GraphRAG 기반 deep research까지
stage 호출 순서, 반복, 분기, provider 조합, pattern version을 관리한다.
"""

from patterns.context import PipelineContext
from patterns.registry import create_pattern, default_pattern_name
from patterns.result import PatternResult

__all__ = [
    "PipelineContext",
    "PatternResult",
    "create_pattern",
    "default_pattern_name",
]
