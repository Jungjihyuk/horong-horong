"""OllamaProvider 단위 테스트."""

import json

import pytest
from pydantic import ValidationError

from contracts.research_artifact import RelevanceJudgment
from providers.ollama_provider import OllamaProvider
from providers.protocols import ProviderOptions


# 시나리오 1. 텍스트 생성은 Ollama generate endpoint에 prompt와 옵션을 전달한다.
@pytest.mark.unit
def test_ollama_provider__generate_text__returns_response_text():
    # Given: 실제 HTTP 호출 대신 요청 payload를 기록하는 transport를 준비한다.
    calls = []

    def fake_transport(url, payload, timeout):
        calls.append((url, payload, timeout))
        return {"response": "생성된 응답\n"}

    provider = OllamaProvider(
        model="qwen3:14b",
        endpoint="http://ollama.test",
        timeout=30,
        transport=fake_transport,
    )

    # When: provider가 텍스트 생성을 수행한다.
    text = provider.generate_text(
        "hello",
        ProviderOptions(temperature=0.2, num_ctx=8192),
    )

    # Then: Ollama 요청 payload와 응답 문자열이 기대한 형태를 가진다.
    assert text == "생성된 응답"
    assert calls[0][0] == "http://ollama.test/api/generate"
    assert calls[0][1]["model"] == "qwen3:14b"
    assert calls[0][1]["prompt"] == "hello"
    assert calls[0][1]["stream"] is False
    assert calls[0][1]["options"] == {"temperature": 0.2, "num_ctx": 8192}
    assert calls[0][2] == 30


# 시나리오 2. 구조화 생성은 Pydantic schema를 Ollama format으로 전달하고 모델로 검증한다.
@pytest.mark.unit
def test_ollama_provider__generate_json__returns_validated_model():
    # Given: RelevanceJudgment JSON 문자열을 반환하는 fake transport를 준비한다.
    calls = []
    response_payload = {
        "item_id": "item-1",
        "is_relevant": True,
        "score": 0.82,
        "threshold": 0.7,
        "matched_keywords": ["AI agent"],
        "reason": "AI agent workflow를 직접 다루므로 관심사와 관련이 높다.",
        "method": "llm",
    }

    def fake_transport(url, payload, timeout):
        calls.append((url, payload, timeout))
        return {"response": json.dumps(response_payload, ensure_ascii=False)}

    provider = OllamaProvider(transport=fake_transport)

    # When: provider가 Pydantic schema에 맞는 JSON 생성을 수행한다.
    judgment = provider.generate_json("judge relevance", RelevanceJudgment)

    # Then: 응답은 RelevanceJudgment 모델로 검증되고 schema가 format에 포함된다.
    assert isinstance(judgment, RelevanceJudgment)
    assert judgment.item_id == "item-1"
    assert judgment.score == 0.82
    assert calls[0][1]["format"]["title"] == "RelevanceJudgment"


# 시나리오 3. 구조화 응답이 artifact 계약을 위반하면 ValidationError로 실패한다.
@pytest.mark.unit
def test_ollama_provider__invalid_json_schema__raises_validation_error():
    # Given: score 범위를 위반하는 JSON 응답을 반환하는 fake transport를 준비한다.
    invalid_payload = {
        "item_id": "item-1",
        "is_relevant": True,
        "score": 1.5,
        "threshold": 0.7,
        "matched_keywords": ["AI agent"],
        "reason": "AI agent workflow를 직접 다루므로 관심사와 관련이 높다.",
    }

    def fake_transport(url, payload, timeout):
        return {"response": json.dumps(invalid_payload, ensure_ascii=False)}

    provider = OllamaProvider(transport=fake_transport)

    # When / Then: Pydantic 검증 단계에서 score 범위 오류를 발생시킨다.
    with pytest.raises(ValidationError) as error:
        provider.generate_json("judge relevance", RelevanceJudgment)

    assert any(err["loc"] == ("score",) for err in error.value.errors())
