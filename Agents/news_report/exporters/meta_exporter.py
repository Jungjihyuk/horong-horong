"""뉴스 리포트 meta JSON exporter."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from patterns.research.result import ResearchResult


def build_report_meta(
    *,
    job_id: str,
    report_date: str,
    generated_at: datetime,
    report_path: str,
    items: list[dict],
    interest_keywords: list[str],
    ontology,
    by_category: dict,
    category_keywords: dict,
    category_trends: dict,
    source_stats: dict,
    warnings: list[str],
) -> dict:
    """Swift 앱과 후속 분석이 읽을 리포트 meta JSON payload를 만든다."""
    return {
        "jobId": job_id,
        "reportDate": report_date,
        "generatedAt": generated_at.astimezone(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "reportPath": report_path,
        "itemCount": len(items),
        "interestKeywords": interest_keywords,
        "ontologySnapshot": [
            {"label": category.label, "keywords": list(category.keywords)}
            for category in ontology.categories
        ],
        "categoryCounts": {
            category: len(category_items)
            for category, category_items in by_category.items()
        },
        "categoryKeywords": category_keywords,
        "categoryTrendSummary": category_trends,
        "topItems": [
            {
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "category": item.get("category", ""),
                "sourceType": item.get("sourceType", ""),
                "importanceScore": item.get("importanceScore", 0),
                "publishedAt": item.get("publishedAt", ""),
                "headline": item.get("headline") or item.get("llmSummary", ""),
            }
            for item in items[:20]
        ],
        "sourceStats": source_stats,
        "warnings": warnings,
    }


def write_meta(path: str, meta: dict) -> None:
    """meta JSON payload를 파일에 기록한다."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as file:
        json.dump(meta, file, ensure_ascii=False, indent=2)


def build_artifact_report_meta(
    *,
    job_id: str,
    report_date: str,
    generated_at: datetime,
    report_path: str,
    research_result: "ResearchResult",
    source_stats: dict,
    warnings: list[str],
) -> dict:
    """research artifact 기반 meta JSON payload를 만든다."""
    assignments_by_candidate_id = {
        assignment.candidate_id: assignment
        for assignment in research_result.category_assignments
    }
    category_counts: dict[str, int] = {}
    for assignment in research_result.category_assignments:
        category_counts[assignment.category_name] = (
            category_counts.get(assignment.category_name, 0) + 1
        )

    return {
        "jobId": job_id,
        "reportDate": report_date,
        "generatedAt": generated_at.astimezone(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "reportPath": report_path,
        "itemCount": len(research_result.source_candidates),
        "interestKeywords": (
            research_result.report_content.interest_keywords
            if research_result.report_content
            else []
        ),
        "researchArtifacts": {
            "sourceItems": [
                item.model_dump(mode="json")
                for item in research_result.source_items
            ],
            "extractedArticles": [
                article.model_dump(mode="json")
                for article in research_result.extracted_articles
            ],
            "keywordMatches": [
                match.model_dump(mode="json")
                for match in research_result.keyword_matches
            ],
            "relevanceJudgments": [
                judgment.model_dump(mode="json")
                for judgment in research_result.relevance_judgments
            ],
            "sourceCandidates": [
                candidate.model_dump(mode="json")
                for candidate in research_result.source_candidates
            ],
            "categoryTaxonomy": (
                research_result.category_taxonomy.model_dump(mode="json")
                if research_result.category_taxonomy
                else None
            ),
            "categoryAssignments": [
                assignment.model_dump(mode="json")
                for assignment in research_result.category_assignments
            ],
            "sourceInsights": [
                insight.model_dump(mode="json")
                for insight in research_result.source_insights
            ],
            "insightBundles": [
                bundle.model_dump(mode="json")
                for bundle in research_result.insight_bundles
            ],
            "keywordInsights": [
                insight.model_dump(mode="json")
                for insight in research_result.keyword_insights
            ],
            "trendInsights": [
                trend.model_dump(mode="json")
                for trend in research_result.trend_insights
            ],
            "reportContent": (
                research_result.report_content.model_dump(mode="json")
                if research_result.report_content
                else None
            ),
        },
        "ontologySnapshot": (
            [
                {
                    "label": category.name,
                    "keywords": list(category.keywords),
                    "description": category.description,
                }
                for category in research_result.category_taxonomy.categories
            ]
            if research_result.category_taxonomy
            else []
        ),
        "categoryCounts": category_counts,
        "topItems": [
            {
                "title": candidate.title,
                "url": candidate.url,
                "category": (
                    assignments_by_candidate_id[candidate.candidate_id].category_name
                    if candidate.candidate_id in assignments_by_candidate_id
                    else "기타"
                ),
                "sourceType": candidate.source_type,
                "importanceScore": 0,
                "relevanceScore": candidate.relevance_score,
                "publishedAt": candidate.published_at or "",
                "headline": (
                    next(
                        (
                            insight.summary
                            for insight in research_result.source_insights
                            if insight.candidate_id == candidate.candidate_id
                        ),
                        "",
                    )
                ),
            }
            for candidate in research_result.source_candidates[:20]
        ],
        "sourceStats": source_stats,
        "warnings": warnings,
    }
