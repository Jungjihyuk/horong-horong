"""research pattern 실행 결과 모델."""

from __future__ import annotations

from dataclasses import dataclass, field

from contracts.research_artifact import (
    CategoryAssignment,
    CategoryTaxonomy,
    ExtractedArticle,
    InsightBundle,
    KeywordInsight,
    KeywordMatch,
    ReportContent,
    RelevanceJudgment,
    SourceCandidate,
    SourceInsight,
    SourceItem,
    TrendInsight,
)


@dataclass
class ResearchResult:
    """research pattern이 생성한 artifact 묶음."""

    source_items: list[SourceItem] = field(default_factory=list)
    extracted_articles: list[ExtractedArticle] = field(default_factory=list)
    keyword_matches: list[KeywordMatch] = field(default_factory=list)
    relevance_judgments: list[RelevanceJudgment] = field(default_factory=list)
    source_candidates: list[SourceCandidate] = field(default_factory=list)
    category_taxonomy: CategoryTaxonomy | None = None
    category_assignments: list[CategoryAssignment] = field(default_factory=list)
    source_insights: list[SourceInsight] = field(default_factory=list)
    insight_bundles: list[InsightBundle] = field(default_factory=list)
    keyword_insights: list[KeywordInsight] = field(default_factory=list)
    trend_insights: list[TrendInsight] = field(default_factory=list)
    report_content: ReportContent | None = None
    warnings: list[str] = field(default_factory=list)
