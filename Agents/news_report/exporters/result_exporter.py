"""Swift 앱이 읽는 runner result JSON exporter."""

from __future__ import annotations

import json
from datetime import datetime, timezone


def build_success_result(
    *,
    job_id: str,
    started_at: str,
    report_path: str,
    meta_path: str,
    source_stats: dict,
    items: list[dict],
    warnings: list[str],
) -> dict:
    """성공 또는 부분 성공 result payload를 만든다."""
    has_failures = any(stats.get("failed", 0) > 0 for stats in source_stats.values())
    status = "partial_success" if has_failures else "success"
    return {
        "jobId": job_id,
        "status": status,
        "startedAt": started_at,
        "endedAt": datetime.now(timezone.utc).isoformat(),
        "reportPath": report_path,
        "metaPath": meta_path,
        "sourceStats": source_stats,
        "topItems": [
            {
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "importanceScore": item.get("importanceScore", 0),
                "category": item.get("category", "기타"),
            }
            for item in items[:5]
        ],
        "warnings": warnings,
        "errorCode": None,
        "errorMessage": None,
    }


def build_failure_result(job_id: str, started_at: str, error: Exception) -> dict:
    """실패 result payload를 만든다."""
    return {
        "jobId": job_id,
        "status": "failed",
        "startedAt": started_at,
        "endedAt": datetime.now(timezone.utc).isoformat(),
        "reportPath": None,
        "metaPath": None,
        "sourceStats": {},
        "topItems": [],
        "warnings": [],
        "errorCode": "E_RUNNER_EXCEPTION",
        "errorMessage": str(error),
    }


def write_result(path: str, result: dict) -> None:
    """runner result JSON payload를 파일에 기록한다."""
    with open(path, "w", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, indent=2)
