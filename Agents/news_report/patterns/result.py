"""pattern 실행 결과 모델."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PatternResult:
    """runner가 result JSON을 만들 때 필요한 pattern 실행 결과."""

    report_path: str
    meta_path: str
    source_stats: dict
    items: list[dict]
    warnings: list[str]
