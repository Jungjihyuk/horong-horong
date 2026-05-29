"""기본 뉴스 리포트 생성 pipeline pattern."""

from __future__ import annotations

from datetime import datetime
from typing import cast

from connectors.collector import collect_sources
from exporters.meta_exporter import build_artifact_report_meta, write_meta
from exporters.report_exporter import write_report
from ontology import load_or_build_for_output_dir
from patterns.context import PipelineContext
from patterns.research import (
    ResearchContext,
    create_research_pattern,
    default_research_pattern_name,
)
from patterns.research.result import ResearchResult
from patterns.result import PatternResult
from providers.protocols import StructuredProvider
from providers.traced_provider import TracedStructuredProvider
from renderers.markdown import render_artifact_markdown_report
from stages.normalize import dedupe_items, normalize_items
from storage.report_paths import build_report_artifact_paths


class NewsReportV1Pipeline:
    """뉴스 수집부터 Markdown 리포트 export까지 수행하는 기본 pipeline."""

    name: str = "news_report_v1"
    version: str = "0.1.0"

    def run(self, context: PipelineContext) -> PatternResult:
        request = context.request
        provider = context.provider
        log = context.log
        step = context.step
        trace = context.trace

        interest_keywords = request.interest_keywords
        max_items = request.max_items_per_source
        output_dir = request.output_dir
        sources = [
            source.model_dump(by_alias=True, exclude_none=True)
            for source in request.sources
        ]
        structured_provider = require_structured_provider(provider)
        if trace:
            structured_provider = TracedStructuredProvider(
                structured_provider,
                trace,
                request.provider,
            )

        step("collect")
        collect_result = collect_sources(sources, max_items, log, trace=trace)
        all_items = collect_result.items
        source_stats = collect_result.source_stats
        warnings = collect_result.warnings

        log(f"Total collected: {len(all_items)} items")

        step("normalize")
        normalized = normalize_items(all_items)
        log(f"Normalized: {len(normalized)}")

        step("dedupe")
        deduped = dedupe_items(normalized)
        log(f"Deduped: {len(deduped)}")

        step("ontology")
        ontology, ontology_status = load_or_build_for_output_dir(
            interest_keywords, provider, output_dir, log_fn=log
        )
        log(
            (
                f"Ontology {ontology_status}: {len(ontology.categories)} categories "
                f"({', '.join(ontology.labels())})"
            )
        )

        step("research")
        research_pattern = create_research_pattern(default_research_pattern_name())
        research_result = research_pattern.run(
            ResearchContext(
                items=deduped,
                interest_keywords=interest_keywords,
                provider=structured_provider,
                log=log,
                trace=trace,
                ontology=ontology,
                relevance_threshold=0.7,
            )
        )
        update_source_stats_used_counts(source_stats, research_result)
        warnings.extend(research_result.warnings)
        log(
            (
                "Research artifacts: "
                f"{len(research_result.source_candidates)} candidates, "
                f"{len(research_result.source_insights)} source insights, "
                f"{len(research_result.insight_bundles)} bundles"
            )
        )

        step("render")
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")
        generated_at_human = now.strftime("%Y-%m-%d %H:%M")
        artifact_paths = build_report_artifact_paths(output_dir, now)

        markdown = render_artifact_markdown_report(
            research_result,
            today_str,
            generated_at_human,
            interest_keywords,
            source_stats,
            warnings,
        )
        report_bytes = write_report(artifact_paths.report_full, markdown)
        log(f"Report written: {artifact_paths.report_full}")
        if trace:
            _ = trace.write(
                "artifact_written",
                payload={
                    "artifact_type": "report",
                    "path": artifact_paths.report_rel,
                    "bytes": report_bytes,
                    "item_count": len(research_result.source_candidates),
                },
            )

        meta = build_artifact_report_meta(
            job_id=request.job_id,
            report_date=today_str,
            generated_at=now,
            report_path=artifact_paths.report_rel,
            research_result=research_result,
            source_stats=source_stats,
            warnings=warnings,
        )
        write_meta(artifact_paths.meta_full, meta)
        if trace:
            _ = trace.write(
                "artifact_written",
                payload={
                    "artifact_type": "meta",
                    "path": artifact_paths.meta_rel,
                    "item_count": len(research_result.source_candidates),
                },
            )

        result_items = result_items_from_research(research_result)
        return PatternResult(
            report_path=artifact_paths.report_rel,
            meta_path=artifact_paths.meta_rel,
            source_stats=source_stats,
            items=result_items,
            warnings=warnings,
        )


def require_structured_provider(provider: object) -> StructuredProvider:
    """artifact 기반 research에 필요한 structured provider인지 확인한다."""
    generate_json = getattr(provider, "generate_json", None)
    if not callable(generate_json):
        raise TypeError(
            (
                "news_report_v1 artifact pipeline requires a StructuredProvider. "
                "Use provider='ollama' or add generate_json() to the provider."
            )
        )
    return cast(StructuredProvider, provider)


def update_source_stats_used_counts(
    source_stats: dict[str, dict[str, object]],
    research_result: ResearchResult,
) -> None:
    """sourceStats.used를 실제 채택된 SourceCandidate 수로 갱신한다."""
    used_by_source: dict[str, int] = {}
    for candidate in research_result.source_candidates:
        used_by_source[candidate.source_type] = (
            used_by_source.get(candidate.source_type, 0) + 1
        )

    for source_type, stats in source_stats.items():
        fetched = int_value(stats.get("fetched"))
        used = used_by_source.get(source_type, 0)
        stats["used"] = used
        stats["filteredOut"] = max(0, fetched - used)


def result_items_from_research(
    research_result: ResearchResult,
) -> list[dict[str, object]]:
    """Swift result JSON 호환 topItems 생성을 위한 item 목록을 만든다."""
    assignments_by_candidate_id = {
        assignment.candidate_id: assignment
        for assignment in research_result.category_assignments
    }
    insights_by_candidate_id = {
        insight.candidate_id: insight
        for insight in research_result.source_insights
    }

    items: list[dict[str, object]] = []
    for candidate in research_result.source_candidates:
        assignment = assignments_by_candidate_id.get(candidate.candidate_id)
        insight = insights_by_candidate_id.get(candidate.candidate_id)
        items.append(
            {
                "title": candidate.title,
                "url": candidate.url,
                "category": assignment.category_name if assignment else "기타",
                "sourceType": candidate.source_type,
                "importanceScore": (
                    int(round(insight.importance_score * 100))
                    if insight
                    else int(round(candidate.relevance_score * 100))
                ),
                "relevanceScore": candidate.relevance_score,
                "headline": insight.summary if insight else "",
            }
        )
    return items


def int_value(value: object) -> int:
    """통계 dict의 값을 int로 안전하게 읽는다."""
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return 0
