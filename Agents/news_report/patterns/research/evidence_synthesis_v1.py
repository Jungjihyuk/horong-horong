"""지정 소스 기반 evidence synthesis research pattern."""

from __future__ import annotations

from patterns.research.context import ResearchContext
from patterns.research.result import ResearchResult
from stages.research_artifacts import (
    assign_categories,
    build_category_taxonomy,
    build_extracted_articles,
    build_insight_bundles,
    build_keyword_insights,
    build_keyword_matches,
    build_report_content,
    build_source_insights,
    build_source_items,
    build_trend_insights,
    utc_now_iso,
)
from stages.relevance_artifacts import select_source_candidates


class EvidenceSynthesisV1Research:
    """수집된 자료를 근거 중심 artifact로 바꾸는 1차 research pattern."""

    name: str = "evidence_synthesis_v1"
    version: str = "0.1.0"

    def run(self, context: ResearchContext) -> ResearchResult:
        """현재는 research artifact 흐름을 붙이기 위한 최소 실행 단위다."""
        context.log(
            f"Research pattern {self.name}: {len(context.items)} items prepared"
        )
        if context.trace:
            _ = context.trace.write(
                "stage_started",
                stage="research",
                payload={
                    "pattern": self.name,
                    "version": self.version,
                    "item_count": len(context.items),
                    "interest_keywords": context.interest_keywords,
                },
            )

        generated_at = utc_now_iso()
        source_items = build_source_items(context.items)
        extracted_articles = build_extracted_articles(
            context.items,
            extracted_at=generated_at,
        )
        keyword_matches = build_keyword_matches(
            extracted_articles,
            context.interest_keywords,
        )
        warnings: list[str] = []

        relevance_judgments, source_candidates = select_source_candidates(
            context.items,
            context.interest_keywords,
            context.provider,
            context.log,
            threshold=context.relevance_threshold,
            warnings=warnings,
            trace=context.trace,
        )
        articles_by_item_id = {
            article.item_id: article
            for article in extracted_articles
        }

        category_taxonomy = None
        category_assignments = []
        source_insights = []
        insight_bundles = []
        keyword_insights = []
        trend_insights = []
        report_content = None
        if context.ontology is not None:
            category_taxonomy = build_category_taxonomy(context.ontology)
            category_assignments = assign_categories(
                source_candidates,
                articles_by_item_id,
                context.ontology,
                category_taxonomy,
            )
            assignments_by_candidate_id = {
                assignment.candidate_id: assignment
                for assignment in category_assignments
            }
            source_insights = build_source_insights(
                source_candidates,
                articles_by_item_id,
                assignments_by_candidate_id,
                context.provider,
                warnings=warnings,
                trace=context.trace,
            )
            insight_bundles = build_insight_bundles(
                source_insights,
                assignments_by_candidate_id,
            )
            source_insights_by_id = {
                insight.source_insight_id: insight
                for insight in source_insights
            }
            keyword_insights = build_keyword_insights(
                insight_bundles,
                source_insights_by_id,
            )
            trend_insights = build_trend_insights(
                insight_bundles,
                source_insights_by_id,
                context.provider,
                warnings=warnings,
                trace=context.trace,
            )
            report_content = build_report_content(
                report_id=f"report-{generated_at}",
                title="뉴스 큐레이션 리포트",
                generated_at=generated_at,
                interest_keywords=context.interest_keywords,
                bundles=insight_bundles,
                keyword_insights=keyword_insights,
                trend_insights=trend_insights,
            )

        if context.trace:
            _ = context.trace.write(
                "stage_completed",
                stage="research",
                payload={
                    "pattern": self.name,
                    "version": self.version,
                    "source_item_count": len(source_items),
                    "extracted_article_count": len(extracted_articles),
                    "keyword_match_count": len(keyword_matches),
                    "relevance_judgment_count": len(relevance_judgments),
                    "source_candidate_count": len(source_candidates),
                    "source_insight_count": len(source_insights),
                    "insight_bundle_count": len(insight_bundles),
                    "trend_insight_count": len(trend_insights),
                    "warning_count": len(warnings),
                },
            )

        return ResearchResult(
            source_items=source_items,
            extracted_articles=extracted_articles,
            keyword_matches=keyword_matches,
            relevance_judgments=relevance_judgments,
            source_candidates=source_candidates,
            category_taxonomy=category_taxonomy,
            category_assignments=category_assignments,
            source_insights=source_insights,
            insight_bundles=insight_bundles,
            keyword_insights=keyword_insights,
            trend_insights=trend_insights,
            report_content=report_content,
            warnings=warnings,
        )
