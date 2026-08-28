"""리포트 생성 과정의 모든 아티팩트를 보존하는 exporter."""

import json
from pathlib import Path
from typing import Any

from contracts.research_artifact import (
    CategoryAssignment,
    CategoryTaxonomy,
    GenerationContext,
    InsightBundle,
    KeywordInsight,
    ReportArtifacts,
    ReportContent,
    SourceCandidate,
    SourceInsight,
    TrendInsight,
)
from storage.report_paths import ReportArtifactPaths


def build_artifacts_dict(
    job_id: str,
    report_date: str,
    generation_context: GenerationContext | None,
    taxonomy: CategoryTaxonomy | None,
    candidates: list[SourceCandidate],
    assignments: list[CategoryAssignment],
    source_insights: list[SourceInsight],
    keyword_insights: list[KeywordInsight],
    trends: list[TrendInsight],
    bundles: list[InsightBundle],
    report_content: ReportContent,
) -> dict[str, Any]:
    artifacts = ReportArtifacts(
        jobId=job_id,
        reportDate=report_date,
        generationContext=generation_context,
        taxonomy=taxonomy,
        candidates=candidates,
        assignments=assignments,
        sourceInsights=source_insights,
        keywordInsights=keyword_insights,
        trends=trends,
        bundles=bundles,
        reportContent=report_content,
    )
    return artifacts.model_dump()

def write_artifacts(paths: ReportArtifactPaths, artifacts_dict: dict[str, Any]) -> None:
    """아티팩트 JSON을 저장한다."""
    artifacts_path = Path(paths.artifacts_full)
    artifacts_path.parent.mkdir(parents=True, exist_ok=True)
    artifacts_path.write_text(json.dumps(artifacts_dict, indent=2, ensure_ascii=False), encoding="utf-8")
