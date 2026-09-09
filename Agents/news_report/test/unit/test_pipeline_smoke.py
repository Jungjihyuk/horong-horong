"""리포트 파이프라인이 끝까지 도는지 확인하는 스모크 테스트.

**왜 있어야 하나**: `NewsReportV1Pipeline.run` 을 실제로 실행하는 테스트가 하나도 없어서,
preflight 를 메서드로 추출할 때 클래스 «바깥» 에 붙인 실수가 잡히지 않았다
(`AttributeError: 'NewsReportV1Pipeline' object has no attribute '_preflight'` — 모든
리포트 실행이 죽는 버그였다). 소스를 비우면 커넥터가 네트워크를 타지 않아 단위 테스트로
run() 전체를 통과시킬 수 있다.
"""

import pytest

from contracts.news_job_request import NewsJobRequest
from patterns.context import PipelineContext
from patterns.pipelines.news_report_v1 import NewsReportV1Pipeline


class SilentProvider:
    """preflight 와 structured 호출을 모두 조용히 받는 fake.

    스키마별로 «검증을 통과하는» 최소 응답을 돌려준다. `schema_model()` 로 빈 인스턴스를
    만들면 필수 필드가 없어 ValidationError 가 나고, 그러면 항목이 하나도 채택되지 않아
    필터 테스트가 조용히 무의미해진다.
    """

    def run(self, prompt: str) -> str:
        return ""

    def generate_text(self, prompt, options=None) -> str:
        return ""

    def generate_json(self, prompt, schema_model, options=None):
        name = schema_model.__name__
        if name == "RelevanceJudgment":
            # 프롬프트에 실린 item_id 를 그대로 돌려줘야 후보로 이어진다.
            item_id = next(
                (line.split("item_id:")[1].strip()
                 for line in prompt.split("\n") if line.startswith("item_id:")),
                "item-unknown",
            )
            return schema_model(
                item_id=item_id, is_relevant=True, score=0.95,
                threshold=0.7, reason="테스트용 관련성 판단 응답입니다.",
            )
        if name == "SourceInsight":
            return schema_model(
                source_insight_id="si-1", candidate_id="c-1",
                summary="요약", importance_score=0.8, why_it_matters="중요",
            )
        try:
            return schema_model()
        except Exception:  # noqa: BLE001 — 나머지 stage 는 실패해도 경고로 넘어간다
            raise RuntimeError(f"{name} 응답을 만들 수 없음")


def make_context(output_dir, steps: list[str]) -> PipelineContext:
    request = NewsJobRequest.model_validate({
        "jobId": "job-smoke",
        "requestedAt": "2026-09-09T09:00:00Z",
        "provider": "ollama",
        "interestKeywords": ["금리"],
        "maxItemsPerSource": 1,
        "dateRangeHours": 24,
        "sources": [],  # 커넥터를 돌리지 않는다
        "outputDir": str(output_dir),
    })
    return PipelineContext(
        request=request,
        provider=SilentProvider(),
        log=lambda _message: None,
        step=steps.append,
        trace=None,
        started_at="2026-09-09T09:00:00Z",
    )


# 시나리오 1. 소스가 없어도 파이프라인은 끝까지 돌고 리포트를 남긴다.
@pytest.mark.unit
def test_pipeline_run__no_sources__completes_and_writes_report(tmp_path):
    # Given: 빈 소스 요청.
    steps: list[str] = []
    context = make_context(tmp_path, steps)

    # When: 파이프라인을 실행한다.
    result = NewsReportV1Pipeline().run(context)

    # Then: 리포트 파일이 남고 주요 stage 가 모두 지나간다.
    assert (tmp_path / result.report_path).exists()
    assert (tmp_path / result.meta_path).exists()
    for expected in ["preflight", "collect", "normalize", "render"]:
        assert expected in steps, f"{expected} stage 가 실행되지 않았다"


# 시나리오 2. preflight 는 파이프라인의 «메서드» 여야 한다.
@pytest.mark.unit
def test_pipeline__preflight_is_an_instance_method():
    # Given/When/Then: 모듈 함수로 새어 나가면 run() 이 AttributeError 로 죽는다.
    assert callable(getattr(NewsReportV1Pipeline, "_preflight", None))


# 시나리오 3. 이미 리포트에 실린 기사는 다음 실행에서 다시 수집하지 않는다.
@pytest.mark.unit
def test_pipeline_run__second_run__skips_already_reported_urls(tmp_path, monkeypatch):
    """이 테스트가 «파이프라인에 실제로 연결됐는지» 를 지킨다.

    스토어 단위 테스트(`test_seen_urls.py`)만으로는 배선이 빠져도 통과한다.
    """
    from connectors.collector import CollectResult
    from storage.seen_urls import load_seen_urls

    items = [
        {"title": "기사 A", "url": "https://a.test/1", "sourceType": "google_news",
         "summary": "본문 A", "publishedAt": "2026-09-09T00:00:00Z"},
        {"title": "기사 B", "url": "https://a.test/2", "sourceType": "google_news",
         "summary": "본문 B", "publishedAt": "2026-09-09T00:00:00Z"},
    ]
    collected: list[int] = []

    def fake_collect(sources, max_items, log, trace=None):
        # 커넥터는 매번 같은 것을 돌려준다 — 실제 RSS 도 그렇다.
        return CollectResult(items=list(items), source_stats={}, warnings=[])

    monkeypatch.setattr(
        "patterns.pipelines.news_report_v1.collect_sources", fake_collect
    )
    # 관련성 판단을 통과시켜 «채택» 되게 한다.
    monkeypatch.setattr(
        "patterns.pipelines.news_report_v1.NewsReportV1Pipeline._preflight",
        lambda self, provider, request, log: None,
    )

    steps: list[str] = []
    NewsReportV1Pipeline().run(make_context(tmp_path, steps))
    after_first = dict(load_seen_urls(str(tmp_path)).entries)

    # When: 같은 소스로 한 번 더 돌린다.
    logs: list[str] = []
    context = make_context(tmp_path, [])
    context.log = logs.append
    NewsReportV1Pipeline().run(context)

    # Then: 첫 실행이 URL 을 기록했고, 둘째 실행은 그것을 건너뛴다.
    assert after_first, "첫 실행에서 채택된 URL 이 기록되어야 한다"
    assert any("already-reported" in line for line in logs), (
        "두 번째 실행이 이미 채택한 URL 을 걸러야 한다"
    )


# 시나리오 4. --ignore-seen 은 필터를 끈다.
@pytest.mark.unit
def test_pipeline_run__ignore_seen__disables_filter(tmp_path):
    from storage.seen_urls import load_seen_urls, record_seen

    store = load_seen_urls(str(tmp_path))
    record_seen(store, ["https://a.test/1"], today="2026-09-01")

    logs: list[str] = []
    context = make_context(tmp_path, [])
    context.log = logs.append
    context.ignore_seen = True

    NewsReportV1Pipeline().run(context)

    assert any("filter disabled" in line for line in logs)
