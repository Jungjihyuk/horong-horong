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
    """preflight 와 structured 호출을 모두 조용히 받는 fake."""

    def run(self, prompt: str) -> str:
        return ""

    def generate_text(self, prompt, options=None) -> str:
        return ""

    def generate_json(self, prompt, schema_model, options=None):
        return schema_model()


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
