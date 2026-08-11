"""뉴스 리포트 산출물 경로 정책."""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class ReportArtifactPaths:
    """한 번의 리포트 실행에서 생성되는 report/meta/artifacts 파일 경로."""

    report_rel: str
    meta_rel: str
    artifacts_rel: str
    report_full: str
    meta_full: str
    artifacts_full: str
    file_stamp: str


def build_report_artifact_paths(
    output_dir: str,
    generated_at: datetime,
) -> ReportArtifactPaths:
    """output_dir와 생성 시각을 기준으로 report/meta/artifacts 경로를 만든다."""
    file_stamp = generated_at.strftime("%Y-%m-%d-%H%M")
    report_rel = f"data/reports/{file_stamp}.md"
    meta_rel = f"data/meta/{file_stamp}.meta.json"
    artifacts_rel = f"data/artifacts/{file_stamp}.artifacts.json"
    return ReportArtifactPaths(
        report_rel=report_rel,
        meta_rel=meta_rel,
        artifacts_rel=artifacts_rel,
        report_full=os.path.join(output_dir, report_rel),
        meta_full=os.path.join(output_dir, meta_rel),
        artifacts_full=os.path.join(output_dir, artifacts_rel),
        file_stamp=file_stamp,
    )
