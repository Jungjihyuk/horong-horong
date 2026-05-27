"""뉴스 리포트 meta JSON exporter."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone


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
