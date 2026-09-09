"""리포트 생성 직후 타임라인 자동 갱신 단위 테스트."""

import json
import sys
from datetime import datetime
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from test_timeline_incrementality import CountingProvider, write_report  # noqa: E402

from timeline.build import build_timeline  # noqa: E402
from timeline.refresh import refresh_existing_timelines  # noqa: E402


@pytest.fixture()
def workspace(tmp_path):
    (tmp_path / "data" / "reports").mkdir(parents=True)
    return tmp_path


def seed_timeline(workspace, provider, now):
    """분야 하나를 미리 만들어 둔다(사용자가 명시적으로 만든 상태)."""
    return build_timeline(
        reports_dir=str(workspace / "data" / "reports"),
        output_dir=str(workspace),
        category_id="macro",
        category_label="금리/거시경제",
        provider=provider,
        provider_name="fake",
        now=now,
    )


# 시나리오 1. 만들어둔 타임라인이 없으면 아무것도 하지 않는다.
@pytest.mark.unit
def test_refresh__no_existing_timelines__does_nothing(workspace):
    # Given: 리포트는 있지만 타임라인은 만든 적이 없다.
    write_report(workspace / "data" / "reports", "2026-09-02", ["기사"])
    provider = CountingProvider()

    # When: 리포트 생성 직후처럼 갱신을 시도한다.
    warnings = refresh_existing_timelines(
        output_dir=str(workspace), provider=provider,
        provider_name="fake", now=datetime(2026, 9, 8),
    )

    # Then: 사용자가 원한 적 없는 분야에 비용을 쓰지 않는다.
    assert provider.calls == []
    assert warnings == []


# 시나리오 2. 리포트가 늘면 이미 있는 타임라인이 자동으로 따라온다.
@pytest.mark.unit
def test_refresh__new_report_added__updates_existing_timeline(workspace):
    # Given: 8월·9월 리포트로 타임라인을 한 번 만들어 두었다.
    reports = workspace / "data" / "reports"
    write_report(reports, "2026-08-11", ["8월 기사"])
    write_report(reports, "2026-09-02", ["9월 기사"])
    now = datetime(2026, 9, 8)
    seed_timeline(workspace, CountingProvider(), now)

    # When: 새 리포트가 한 편 더 생긴 뒤 갱신이 돈다.
    write_report(reports, "2026-09-08", ["오늘 들어온 기사"])
    provider = CountingProvider()
    warnings = refresh_existing_timelines(
        output_dir=str(workspace), provider=provider, provider_name="fake", now=now,
    )

    # Then: 현재 월 1회 + 개요 1회. 봉인된 8월은 건드리지 않는다.
    assert provider.month_calls == 1
    assert provider.overview_calls == 1
    assert warnings == []

    state = json.loads(
        (workspace / "data" / "timeline" / "macro.json").read_text(encoding="utf-8")
    )
    september = next(m for m in state["months"] if m["month_key"] == "2026-09")
    assert "오늘 들어온 기사" in json.dumps(september, ensure_ascii=False)


# 시나리오 3. 마크다운도 함께 다시 쓴다 — 화면과 파일이 어긋나면 안 된다.
@pytest.mark.unit
def test_refresh__writes_markdown_alongside_state(workspace):
    # Given: 타임라인이 하나 있다.
    reports = workspace / "data" / "reports"
    write_report(reports, "2026-09-02", ["기사"])
    now = datetime(2026, 9, 8)
    seed_timeline(workspace, CountingProvider(), now)

    # When: 새 리포트 뒤 갱신이 돈다.
    write_report(reports, "2026-09-08", ["새 기사"])
    refresh_existing_timelines(
        output_dir=str(workspace), provider=CountingProvider(),
        provider_name="fake", now=now,
    )

    # Then: 마크다운 산출물이 생긴다.
    assert (workspace / "data" / "timelines" / "macro.md").exists()


# 시나리오 4. 타임라인 갱신이 실패해도 예외를 올리지 않는다.
@pytest.mark.unit
def test_refresh__provider_failure__reports_warning_without_raising(workspace):
    # Given: 타임라인이 하나 있고, provider 가 터진다.
    reports = workspace / "data" / "reports"
    write_report(reports, "2026-09-02", ["기사"])
    now = datetime(2026, 9, 8)
    seed_timeline(workspace, CountingProvider(), now)
    write_report(reports, "2026-09-08", ["새 기사"])

    class BrokenProvider:
        def generate_json(self, prompt, schema_model, options=None):
            raise RuntimeError("provider 가 죽었다")

    # When: 갱신을 시도한다.
    warnings = refresh_existing_timelines(
        output_dir=str(workspace), provider=BrokenProvider(),
        provider_name="fake", now=now,
    )

    # Then: 리포트 job 을 실패시키지 않고 경고만 남긴다.
    assert any("2026-09" in warning for warning in warnings)


# 시나리오 5. 상태 파일이 깨져도 나머지 분야는 갱신된다.
@pytest.mark.unit
def test_refresh__corrupt_state_file__skips_only_that_category(workspace):
    # Given: 정상 타임라인 하나와 깨진 파일 하나.
    reports = workspace / "data" / "reports"
    write_report(reports, "2026-09-02", ["기사"])
    now = datetime(2026, 9, 8)
    seed_timeline(workspace, CountingProvider(), now)
    (workspace / "data" / "timeline" / "broken.json").write_text("{ 깨짐", encoding="utf-8")
    write_report(reports, "2026-09-08", ["새 기사"])

    # When: 갱신이 돈다.
    provider = CountingProvider()
    warnings = refresh_existing_timelines(
        output_dir=str(workspace), provider=provider, provider_name="fake", now=now,
    )

    # Then: 깨진 것만 경고로 남고 정상 분야는 갱신된다.
    assert any("broken" in warning for warning in warnings)
    assert provider.month_calls == 1
