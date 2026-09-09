"""월 봉인 기반 점진적 갱신 단위 테스트.

이 파일이 타임라인 기능의 존재 이유를 지킨다. 리포트가 늘어도 LLM 호출 수가 리포트
수에 비례하지 않아야 한다 — 그 성질이 깨지면 여기서 빨간불이 켜져야 한다.
"""

from datetime import datetime

import pytest

from contracts.timeline_artifact import MonthSynthesis, OverviewSynthesis
from timeline.build import build_timeline
from timeline.state import load_state


class CountingProvider:
    """StructuredProvider 계약을 만족하며 호출 횟수를 세는 fake.

    응답은 결정적이다. 이 테스트가 검증하는 것은 종합 «품질» 이 아니라 종합을
    «몇 번 하는가» 이므로, 모델을 부르면 안 된다.
    """

    def __init__(self) -> None:
        self.calls: list[str] = []

    def generate_json(self, prompt, schema_model, options=None):
        self.calls.append(schema_model.__name__)
        if schema_model is MonthSynthesis:
            # 프롬프트에 실린 event_id 를 하나 골라 축으로 삼는다.
            event_ids = [
                line.split("event_id:")[1].strip()
                for line in prompt.split("\n")
                if "event_id:" in line
            ]
            return MonthSynthesis(
                summary="이 달의 종합.",
                key_terms=["키워드"],
                assessments=[
                    {
                        "event_id": event_id,
                        "duplicate_group": event_id,
                        "assessment": {
                            "change_magnitude": 20,
                            "impact_scope": 20,
                            "durability": 15,
                            "trajectory_power": 15,
                            "evidence_strength": 10,
                            "reason": "공통 루브릭 평가 근거.",
                        },
                    }
                    for event_id in event_ids
                ],
                axis=[{"event_id": event_ids[0], "why_it_matters": "축인 이유."}],
            )
        return OverviewSynthesis(summary="전체 흐름.", emphasis_keywords=["강조어"])

    @property
    def month_calls(self) -> int:
        return self.calls.count("MonthSynthesis")

    @property
    def overview_calls(self) -> int:
        return self.calls.count("OverviewSynthesis")

    @property
    def total_calls(self) -> int:
        return len(self.calls)


def write_report(reports_dir, date: str, titles: list[str]) -> None:
    """최소한의 리포트 마크다운 1편을 만든다."""
    items = "\n\n".join(
        f"### {index + 1}. [{title}](https://example.com/{date}/{index})\n"
        f"> 중요도: {90 - index}/100 | 관련성: 90/100 | google_news | {date}"
        for index, title in enumerate(titles)
    )
    (reports_dir / f"{date}-0900.md").write_text(
        f"# 뉴스 큐레이션 리포트 - {date}\n\n"
        f"## 금리/거시경제\n"
        f"🔑 키워드: 금리, 물가\n"
        f"📈 트렌드: {date} 의 흐름 요약입니다.\n\n"
        f"{items}\n",
        encoding="utf-8",
    )


@pytest.fixture()
def workspace(tmp_path):
    reports = tmp_path / "data" / "reports"
    reports.mkdir(parents=True)
    return tmp_path, reports


def build(workspace, provider, now, **kwargs):
    output_dir, reports = workspace
    return build_timeline(
        reports_dir=str(reports),
        output_dir=str(output_dir),
        category_id="macro",
        category_label="금리/거시경제",
        provider=provider,
        provider_name="fake",
        now=now,
        **kwargs,
    )


# 시나리오 1. 최초 빌드는 월 수만큼만 종합하고 개요를 한 번 만든다.
@pytest.mark.unit
def test_build_timeline__cold_start__calls_once_per_month_plus_overview(workspace):
    # Given: 4개월에 걸친 리포트 6편이 쌓여 있다.
    _, reports = workspace
    for date in ["2026-03-02", "2026-03-20", "2026-04-05", "2026-05-11", "2026-05-30", "2026-06-08"]:
        write_report(reports, date, [f"{date} 기사"])
    provider = CountingProvider()

    # When: 처음으로 타임라인을 만든다.
    result = build(workspace, provider, datetime(2026, 6, 15))

    # Then: 달마다 1회 + 개요 1회. 리포트 6편이 아니라 «개월 수» 에 비례한다.
    assert provider.month_calls == 4
    assert provider.overview_calls == 1
    assert result.total_calls == 5


# 시나리오 2. 새 문서 1건이 현재 월에 들어오면 그 달과 개요만 다시 만든다.
@pytest.mark.unit
def test_build_timeline__new_document_in_open_month__recomputes_only_open_month(workspace):
    # Given: 이미 한 번 빌드해 4개월이 종합되어 있다.
    _, reports = workspace
    for date in ["2026-03-02", "2026-04-05", "2026-05-11", "2026-06-08"]:
        write_report(reports, date, [f"{date} 기사"])
    now = datetime(2026, 6, 15)
    build(workspace, CountingProvider(), now)

    sealed_before = {
        month.month_key: month.synthesized_at
        for month in load_state(
            str(workspace[0] / "data" / "timeline" / "macro.json")
        ).months
        if month.month_key < "2026-06"
    }

    # When: 오늘(현재 월)에 리포트 1편이 더 쌓인 뒤 다시 빌드한다.
    write_report(reports, "2026-06-14", ["새로 들어온 기사"])
    provider = CountingProvider()
    build(workspace, provider, now)

    # Then: 현재 월 1회 + 개요 1회뿐. 봉인된 달은 종합 시각조차 그대로다.
    assert provider.month_calls == 1
    assert provider.overview_calls == 1
    state = load_state(str(workspace[0] / "data" / "timeline" / "macro.json"))
    sealed_after = {
        month.month_key: month.synthesized_at
        for month in state.months
        if month.month_key < "2026-06"
    }
    assert sealed_after == sealed_before


# 시나리오 3. 리포트가 계속 늘어도 실행당 호출 수는 상수로 유지된다.
@pytest.mark.unit
def test_build_timeline__reports_keep_accumulating__calls_per_run_stay_constant(workspace):
    # Given: 3개월치가 이미 종합되어 있다.
    _, reports = workspace
    for date in ["2026-04-05", "2026-05-11", "2026-06-02"]:
        write_report(reports, date, [f"{date} 기사"])
    now = datetime(2026, 6, 20)
    build(workspace, CountingProvider(), now)

    # When: 현재 월에 하루 한 편씩 5일 더 쌓으며 매일 다시 빌드한다.
    per_run: list[int] = []
    for day in range(10, 15):
        write_report(reports, f"2026-06-{day}", [f"6월 {day}일 기사"])
        provider = CountingProvider()
        build(workspace, provider, now)
        per_run.append(provider.month_calls + provider.overview_calls)

    # Then: 매 실행이 2회로 고정된다 — 누적 문서 수와 무관하다.
    assert per_run == [2, 2, 2, 2, 2]


# 시나리오 4. 바뀐 것이 없으면 LLM 을 한 번도 부르지 않는다.
@pytest.mark.unit
def test_build_timeline__nothing_changed__makes_no_calls(workspace):
    # Given: 빌드를 이미 마친 상태다.
    _, reports = workspace
    write_report(reports, "2026-05-11", ["기사"])
    now = datetime(2026, 6, 15)
    build(workspace, CountingProvider(), now)

    # When: 새 리포트 없이 다시 빌드한다.
    provider = CountingProvider()
    build(workspace, provider, now)

    # Then: 월도 개요도 부르지 않는다.
    assert provider.calls == []


# 시나리오 5. 봉인된 달로 뒤늦게 사건이 들어와도 그 달은 건드리지 않는다.
@pytest.mark.unit
def test_build_timeline__backdated_report_into_sealed_month__leaves_it_untouched(workspace):
    # Given: 5월과 6월이 종합되어 있고 5월은 봉인 상태다.
    _, reports = workspace
    write_report(reports, "2026-05-11", ["5월 기사"])
    write_report(reports, "2026-06-02", ["6월 기사"])
    now = datetime(2026, 6, 20)
    build(workspace, CountingProvider(), now)
    path = str(workspace[0] / "data" / "timeline" / "macro.json")
    may_before = next(m for m in load_state(path).months if m.month_key == "2026-05")

    # When: 5월 날짜의 리포트가 뒤늦게 추가된 뒤 다시 빌드한다.
    write_report(reports, "2026-05-28", ["뒤늦게 들어온 5월 기사"])
    provider = CountingProvider()
    build(workspace, provider, now)

    # Then: 5월은 그대로다. 되살리려면 --rebuild 를 명시해야 한다.
    may_after = next(m for m in load_state(path).months if m.month_key == "2026-05")
    assert may_after == may_before
    assert provider.month_calls == 0


# 시나리오 6. --rebuild 는 봉인을 무시하고 전부 다시 만든다.
@pytest.mark.unit
def test_build_timeline__rebuild__resynthesizes_every_month(workspace):
    # Given: 3개월이 종합되어 있다.
    _, reports = workspace
    for date in ["2026-04-05", "2026-05-11", "2026-06-02"]:
        write_report(reports, date, [f"{date} 기사"])
    now = datetime(2026, 6, 20)
    build(workspace, CountingProvider(), now)

    # When: rebuild 로 다시 만든다.
    provider = CountingProvider()
    build(workspace, provider, now, rebuild=True)

    # Then: 봉인 여부와 무관하게 3개월 전부 + 개요.
    assert provider.month_calls == 3
    assert provider.overview_calls == 1


# 시나리오 7. dry-run 은 계획만 알려주고 LLM 을 부르지 않는다.
@pytest.mark.unit
def test_build_timeline__dry_run__reports_plan_without_calling_provider(workspace):
    # Given: 2개월치 리포트가 있고 아직 빌드한 적이 없다.
    _, reports = workspace
    write_report(reports, "2026-05-11", ["5월 기사"])
    write_report(reports, "2026-06-02", ["6월 기사"])

    # When: dry-run 으로 실행한다.
    provider = CountingProvider()
    result = build(workspace, provider, datetime(2026, 6, 20), dry_run=True)

    # Then: 호출은 0회이고, 상태 파일도 쓰지 않는다.
    assert provider.calls == []
    assert sum(1 for plan in result.plans if plan.needs_synthesis) == 2
    assert not (workspace[0] / "data" / "timeline" / "macro.json").exists()


# 시나리오 8. 대표 최대치를 바꾸면 봉인된 달도 새 설정으로 다시 종합한다.
@pytest.mark.unit
def test_build_timeline__axis_limit_changed__resynthesizes_all_months(workspace):
    _, reports = workspace
    write_report(reports, "2026-05-11", ["5월 기사"])
    write_report(reports, "2026-06-02", ["6월 기사"])
    now = datetime(2026, 6, 20)
    build(workspace, CountingProvider(), now, axis_limit=3)

    provider = CountingProvider()
    build(workspace, provider, now, axis_limit=5)

    state = load_state(str(workspace[0] / "data" / "timeline" / "macro.json"))
    assert provider.month_calls == 2
    assert state.axis_limit == 5


class FlakyProvider(CountingProvider):
    """지정한 달의 프롬프트에서만 터지는 fake. 부분 실패를 재현한다."""

    def __init__(self, failing_month: str) -> None:
        super().__init__()
        self.failing_month = failing_month

    def generate_json(self, prompt, schema_model, options=None):
        if schema_model is MonthSynthesis and self.failing_month in prompt:
            self.calls.append(schema_model.__name__)
            raise ValueError("모델이 JSON 을 반환하지 않았습니다")
        return super().generate_json(prompt, schema_model, options)


# 시나리오 9. 한 달이 실패해도 나머지 달의 종합 결과는 저장된다.
@pytest.mark.unit
def test_build_timeline__one_month_fails__other_months_are_still_saved(workspace):
    # Given: 3개월치 리포트가 있고 5월 종합이 실패한다.
    _, reports = workspace
    for date in ["2026-04-05", "2026-05-11", "2026-06-02"]:
        write_report(reports, date, [f"{date} 기사"])

    # When: 빌드한다.
    result = build(workspace, FlakyProvider("2026-05"), datetime(2026, 6, 20))

    # Then: 빌드는 끝까지 가고, 성공한 달은 저장되며, 실패는 경고로 남는다.
    state = load_state(str(workspace[0] / "data" / "timeline" / "macro.json"))
    assert state is not None, "부분 실패에도 상태 파일은 저장되어야 한다"
    synthesized = {m.month_key for m in state.months if m.synthesized_at}
    assert synthesized == {"2026-04", "2026-06"}
    assert any("2026-05" in warning for warning in state.warnings)
    assert result.state.warnings


# 시나리오 10. 다음 실행은 실패했던 달만 다시 잡는다.
@pytest.mark.unit
def test_build_timeline__rerun_after_failure__retries_only_failed_month(workspace):
    # Given: 5월이 실패한 채로 한 번 빌드가 끝났다.
    _, reports = workspace
    for date in ["2026-04-05", "2026-05-11", "2026-06-02"]:
        write_report(reports, date, [f"{date} 기사"])
    now = datetime(2026, 6, 20)
    build(workspace, FlakyProvider("2026-05"), now)

    # When: 정상 provider 로 다시 빌드한다.
    provider = CountingProvider()
    build(workspace, provider, now)

    # Then: 봉인된 4월은 건드리지 않고 5월만 다시 종합한다(+개요).
    assert provider.month_calls == 1
    state = load_state(str(workspace[0] / "data" / "timeline" / "macro.json"))
    assert all(month.synthesized_at for month in state.months)
    assert state.warnings == []
