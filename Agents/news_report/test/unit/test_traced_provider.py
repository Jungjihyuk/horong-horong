"""TracedStructuredProvider 단위 테스트."""

from __future__ import annotations

from collections.abc import Mapping
from typing import TypedDict, cast

import pytest
from pydantic import BaseModel

from contracts.research_artifact import RelevanceJudgment
from providers.protocols import ProviderOptions, StructuredModel
from providers.traced_provider import TracedStructuredProvider
from tracing.events import TraceEventName


class TraceRecord(TypedDict):
    event: TraceEventName
    stage: str | None
    duration_ms: int | None
    payload: dict[str, object]


class FakeStructuredProvider:
    """trace wrapper 아래에서 동작하는 structured provider fake."""

    def __init__(self, response: BaseModel | Exception):
        self.response: BaseModel | Exception = response
        self.prompts: list[str] = []

    def run(self, prompt: str) -> str:
        self.prompts.append(prompt)
        return "text"

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        _ = options
        self.prompts.append(prompt)
        return "text"

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        _ = schema_model
        _ = options
        self.prompts.append(prompt)
        if isinstance(self.response, Exception):
            raise self.response
        return cast(StructuredModel, self.response)


class FakeTrace:
    """TraceWriter 대신 이벤트를 메모리에 쌓는 fake."""

    def __init__(self):
        self.events: list[TraceRecord] = []

    def write(
        self,
        event: TraceEventName,
        *,
        stage: str | None = None,
        duration_ms: int | None = None,
        payload: Mapping[str, object] | None = None,
        **payload_fields: object,
    ) -> object:
        merged_payload = dict(payload or {})
        merged_payload.update(payload_fields)
        record: TraceRecord = {
            "event": event,
            "stage": stage,
            "duration_ms": duration_ms,
            "payload": merged_payload,
        }
        self.events.append(record)
        return record


# 시나리오 1. structured output 생성이 성공하면 시작/완료 이벤트가 trace에 남는다.
@pytest.mark.unit
def test_traced_provider__generate_json_success__writes_started_and_completed_events():
    # Given: 유효한 RelevanceJudgment를 반환하는 provider와 fake trace를 준비한다.
    judgment = RelevanceJudgment(
        item_id="item-1",
        is_relevant=True,
        score=0.82,
        threshold=0.7,
        matched_keywords=["AI agent"],
        reason="AI agent workflow를 직접 다루므로 관련이 높다.",
        method="llm",
    )
    trace = FakeTrace()
    provider = TracedStructuredProvider(
        FakeStructuredProvider(judgment),
        trace,
        provider_name="ollama",
    )

    # When: traced provider를 통해 structured output을 생성한다.
    result = provider.generate_json(
        "judge relevance",
        RelevanceJudgment,
        ProviderOptions(temperature=0.1),
    )

    # Then: provider_started/provider_completed 이벤트에 schema와 provider 정보가 기록된다.
    assert result == judgment
    assert [event["event"] for event in trace.events] == [
        "provider_started",
        "provider_completed",
    ]
    assert trace.events[0]["stage"] == "provider.generate_json"
    assert trace.events[0]["payload"]["operation"] == "structured_output"
    assert trace.events[0]["payload"]["provider"] == "ollama"
    assert trace.events[0]["payload"]["schema"] == "RelevanceJudgment"
    assert trace.events[0]["payload"]["prompt_chars"] == len("judge relevance")
    assert trace.events[0]["payload"]["options"] == {"temperature": 0.1}
    assert trace.events[1]["payload"]["result_model"] == "RelevanceJudgment"
    assert isinstance(trace.events[1]["duration_ms"], int)


# 시나리오 2. structured output 생성이 실패하면 실패 이벤트를 남기고 예외를 다시 올린다.
@pytest.mark.unit
def test_traced_provider__generate_json_failure__writes_failed_event():
    # Given: structured output 생성 중 실패하는 provider와 fake trace를 준비한다.
    trace = FakeTrace()
    provider = TracedStructuredProvider(
        FakeStructuredProvider(ValueError("invalid json")),
        trace,
        provider_name="claude",
    )

    # When / Then: 예외는 호출자에게 전달되고 provider_failed 이벤트가 기록된다.
    with pytest.raises(ValueError, match="invalid json"):
        _ = provider.generate_json("judge relevance", RelevanceJudgment)

    assert [event["event"] for event in trace.events] == [
        "provider_started",
        "provider_failed",
    ]
    assert trace.events[1]["payload"]["provider"] == "claude"
    assert trace.events[1]["payload"]["operation"] == "structured_output"
    assert trace.events[1]["payload"]["error_type"] == "ValueError"
    assert trace.events[1]["payload"]["error_message"] == "invalid json"


def _sample_judgment() -> RelevanceJudgment:
    return RelevanceJudgment(
        item_id="item-1",
        is_relevant=True,
        score=0.82,
        threshold=0.7,
        matched_keywords=["AI agent"],
        reason="AI agent workflow를 직접 다루므로 관련이 높다.",
        method="llm",
    )


# 시나리오 3. wrapped provider가 repair 여부를 노출하면 completed payload에 싣는다.
@pytest.mark.unit
def test_traced_provider__provider_exposes_repair__records_repair_attempted():
    # Given: BaseCliProvider처럼 _last_repair_attempted를 노출하는 provider를 모사한다.
    inner = FakeStructuredProvider(_sample_judgment())
    inner._last_repair_attempted = True
    trace = FakeTrace()
    provider = TracedStructuredProvider(inner, trace, provider_name="claude")

    # When: traced provider로 structured output을 생성한다.
    _ = provider.generate_json("judge relevance", RelevanceJudgment)

    # Then: provider_completed payload에 repair_attempted=True가 기록된다.
    assert trace.events[1]["event"] == "provider_completed"
    assert trace.events[1]["payload"]["repair_attempted"] is True


# 시나리오 4. provider가 repair 여부를 노출하지 않으면 repair_attempted를 생략한다.
@pytest.mark.unit
def test_traced_provider__no_repair_attribute__omits_repair_attempted():
    # Given: repair 속성이 없는 provider(예: Ollama)를 준비한다.
    trace = FakeTrace()
    provider = TracedStructuredProvider(
        FakeStructuredProvider(_sample_judgment()),
        trace,
        provider_name="ollama",
    )

    # When: traced provider로 structured output을 생성한다.
    _ = provider.generate_json("judge relevance", RelevanceJudgment)

    # Then: repair_attempted 키 자체가 payload에 없다.
    assert "repair_attempted" not in trace.events[1]["payload"]
