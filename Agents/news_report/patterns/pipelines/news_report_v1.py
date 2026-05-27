"""기본 뉴스 리포트 생성 pipeline pattern."""

from __future__ import annotations

from datetime import datetime

from connectors.collector import collect_sources
from exporters.meta_exporter import build_report_meta, write_meta
from exporters.report_exporter import write_report
from ontology import load_or_build_for_output_dir
from patterns.context import PipelineContext
from patterns.result import PatternResult
from renderers.markdown import render_markdown_report
from stages.classify import classify_items
from stages.normalize import dedupe_items, normalize_items
from stages.ranking import rank_items
from stages.relevance import filter_relevance
from stages.summarize import summarize_items, summarize_transcripts
from stages.trends import extract_keyword_stats, summarize_category_trends
from storage.report_paths import build_report_artifact_paths


class NewsReportV1Pipeline:
    """뉴스 수집부터 Markdown 리포트 export까지 수행하는 기본 pipeline."""

    name = "news_report_v1"
    version = "0.1.0"

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
            f"Ontology {ontology_status}: {len(ontology.categories)} categories "
            f"({', '.join(ontology.labels())})"
        )

        step("classify")
        classified = classify_items(deduped, ontology)
        log(f"Classified: {len(classified)}")

        step("relevance_filter")
        filtered, dropped_count = filter_relevance(
            classified, interest_keywords, provider, log
        )
        youtube_stats = source_stats.get("youtube")
        if youtube_stats is not None:
            youtube_stats["used"] = sum(
                1 for item in filtered if item.get("sourceType") == "youtube"
            )
            youtube_stats["filteredOut"] = dropped_count
        log(f"Relevance-filtered: {len(filtered)}")

        step("rank")
        ranked = rank_items(filtered, interest_keywords, ontology)
        log(f"Ranked: {len(ranked)}")

        step("summarize")
        ranked = summarize_transcripts(ranked, interest_keywords, provider, log)
        summarized = summarize_items(ranked, interest_keywords, provider, log)

        by_category: dict = {}
        for item in summarized:
            category = item.get("category", "기타")
            by_category.setdefault(category, []).append(item)

        step("trend_summary")
        category_keywords = {
            category: extract_keyword_stats(items, top_n=5)
            for category, items in by_category.items()
        }
        category_trends = summarize_category_trends(by_category, provider, log)
        log(f"Trend summary: {len(category_trends)} category 요약 생성")

        step("render")
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")
        generated_at_human = now.strftime("%Y-%m-%d %H:%M")
        artifact_paths = build_report_artifact_paths(output_dir, now)

        markdown = render_markdown_report(
            summarized,
            today_str,
            generated_at_human,
            interest_keywords,
            source_stats,
            warnings,
            ontology,
            category_keywords,
            category_trends,
        )
        report_bytes = write_report(artifact_paths.report_full, markdown)
        log(f"Report written: {artifact_paths.report_full}")
        if trace:
            trace.write(
                "artifact_written",
                payload={
                    "artifact_type": "report",
                    "path": artifact_paths.report_rel,
                    "bytes": report_bytes,
                    "item_count": len(summarized),
                },
            )

        meta = build_report_meta(
            job_id=request.job_id,
            report_date=today_str,
            generated_at=now,
            report_path=artifact_paths.report_rel,
            items=summarized,
            interest_keywords=interest_keywords,
            ontology=ontology,
            by_category=by_category,
            category_keywords=category_keywords,
            category_trends=category_trends,
            source_stats=source_stats,
            warnings=warnings,
        )
        write_meta(artifact_paths.meta_full, meta)
        if trace:
            trace.write(
                "artifact_written",
                payload={
                    "artifact_type": "meta",
                    "path": artifact_paths.meta_rel,
                    "item_count": len(summarized),
                },
            )

        return PatternResult(
            report_path=artifact_paths.report_rel,
            meta_path=artifact_paths.meta_rel,
            source_stats=source_stats,
            items=summarized,
            warnings=warnings,
        )
