"""리포트 산출물 경로 정책 단위 테스트."""

from datetime import datetime

import pytest

from storage.report_paths import build_report_artifact_paths


# 시나리오 1. 생성 시각과 output_dir을 기준으로 report/meta 경로를 만든다.
@pytest.mark.unit
def test_build_report_artifact_paths__fixed_datetime__returns_report_and_meta_paths():
    # Given: 리포트 생성 시각과 output_dir을 준비한다.
    generated_at = datetime(2026, 5, 27, 10, 30)

    # When: report artifact 경로를 생성한다.
    paths = build_report_artifact_paths("/tmp/news", generated_at)

    # Then: 분 단위 timestamp를 포함한 상대/절대 경로가 만들어진다.
    assert paths.file_stamp == "2026-05-27-1030"
    assert paths.report_rel == "data/reports/2026-05-27-1030.md"
    assert paths.meta_rel == "data/meta/2026-05-27-1030.meta.json"
    assert paths.report_full == "/tmp/news/data/reports/2026-05-27-1030.md"
    assert paths.meta_full == "/tmp/news/data/meta/2026-05-27-1030.meta.json"
