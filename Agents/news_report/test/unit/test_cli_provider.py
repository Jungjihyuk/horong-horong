"""CLI provider structured output 단위 테스트."""

import json
from typing import override

import pytest
from pydantic import ValidationError

from contracts.research_artifact import RelevanceJudgment
from providers.base_provider import (
    BaseCliProvider,
    build_json_repair_prompt,
    build_structured_prompt,
    extract_json_object,
)
from providers.protocols import ProviderOptions


class FakeCliProvider(BaseCliProvider):
    """subprocess 대신 미리 준비한 응답을 반환하는 CLI provider fake."""

    def __init__(self, response: str):
        self.response: str = response
        self.prompts: list[str] = []

    @override
    def _build_command(self, prompt: str) -> list[str]:
        return ["fake-cli", prompt]

    @override
    def run(self, prompt: str) -> str:
        self.prompts.append(prompt)
        return self.response


class QueueCliProvider(BaseCliProvider):
    """호출 순서대로 다른 응답을 반환하는 CLI provider fake."""

    def __init__(self, responses: list[str]):
        self.responses: list[str] = responses
        self.prompts: list[str] = []

    @override
    def _build_command(self, prompt: str) -> list[str]:
        return ["fake-cli", prompt]

    @override
    def run(self, prompt: str) -> str:
        self.prompts.append(prompt)
        return self.responses.pop(0)


# 시나리오 1. CLI structured prompt는 원본 prompt와 JSON schema 지시문을 포함한다.
@pytest.mark.unit
def test_build_structured_prompt__schema_model__includes_json_schema():
    # Given: relevance 판단 prompt와 Pydantic schema를 준비한다.
    prompt = "judge relevance"

    # When: CLI provider용 structured prompt를 만든다.
    structured_prompt = build_structured_prompt(prompt, RelevanceJudgment)

    # Then: 원본 prompt, JSON-only 지시문, schema 이름이 포함된다.
    assert "judge relevance" in structured_prompt
    assert "JSON Schema:" in structured_prompt
    assert "RelevanceJudgment" in structured_prompt
    assert "Markdown 코드 블록" in structured_prompt


# 시나리오 2. CLI 응답이 코드 블록을 포함해도 JSON object만 추출한다.
@pytest.mark.unit
def test_extract_json_object__fenced_json_response__returns_json_string():
    # Given: CLI agent가 Markdown 코드 블록으로 감싼 JSON을 반환한다.
    text = '설명\n```json\n{"score": 1}\n```\n'

    # When: JSON object 추출을 수행한다.
    extracted = extract_json_object(text)

    # Then: 코드 블록 안의 JSON 문자열만 반환된다.
    assert extracted == '{"score": 1}'


# 시나리오 3. JSON repair prompt는 실패 응답과 schema를 함께 전달한다.
@pytest.mark.unit
def test_build_json_repair_prompt__invalid_response__asks_json_only():
    # Given: JSON object가 없는 CLI 응답과 파싱 오류를 준비한다.
    raw_response = "관련성이 높습니다. 점수는 0.8입니다."
    error = ValueError("JSON object 없음")

    # When: repair prompt를 만든다.
    prompt = build_json_repair_prompt(raw_response, RelevanceJudgment, error)

    # Then: 이전 응답, 오류, JSON-only 지시문, schema가 포함된다.
    assert "이전 응답이 JSON schema 검증에 실패했습니다." in prompt
    assert "관련성이 높습니다" in prompt
    assert "JSON Schema:" in prompt
    assert "RelevanceJudgment" in prompt


# 시나리오 4. CLI provider는 JSON 응답을 Pydantic 모델로 검증해 반환한다.
@pytest.mark.unit
def test_cli_provider__generate_json__returns_validated_model():
    # Given: RelevanceJudgment JSON을 반환하는 CLI provider fake를 준비한다.
    response_payload = {
        "item_id": "item-1",
        "is_relevant": True,
        "score": 0.82,
        "threshold": 0.7,
        "matched_keywords": ["AI agent"],
        "reason": "AI agent workflow를 직접 다루므로 관심사와 관련이 높다.",
        "method": "llm",
    }
    provider = FakeCliProvider(json.dumps(response_payload, ensure_ascii=False))

    # When: CLI provider structured generation을 실행한다.
    judgment = provider.generate_json(
        "judge relevance",
        RelevanceJudgment,
        ProviderOptions(temperature=0.1),
    )

    # Then: 응답은 RelevanceJudgment 모델로 검증되고 prompt에는 schema가 포함된다.
    assert isinstance(judgment, RelevanceJudgment)
    assert judgment.score == 0.82
    assert "JSON Schema:" in provider.prompts[0]


# 시나리오 5. CLI provider는 첫 응답에 JSON이 없으면 repair prompt로 재시도한다.
@pytest.mark.unit
def test_cli_provider__missing_json_then_repair__returns_validated_model():
    # Given: 첫 응답은 설명문뿐이고 두 번째 응답은 유효한 JSON인 CLI provider fake를 준비한다.
    repaired_payload = {
        "item_id": "item-1",
        "is_relevant": True,
        "score": 0.8,
        "threshold": 0.7,
        "matched_keywords": ["AI agent"],
        "reason": "AI agent workflow를 직접 다루므로 관심사와 관련이 높다.",
        "method": "llm",
    }
    provider = QueueCliProvider(
        [
            "관련성이 높습니다. 점수는 0.8입니다.",
            json.dumps(repaired_payload, ensure_ascii=False),
        ]
    )

    # When: CLI provider structured generation을 실행한다.
    judgment = provider.generate_json("judge relevance", RelevanceJudgment)

    # Then: repair 호출 후 RelevanceJudgment 모델이 반환된다.
    assert judgment.score == 0.8
    assert len(provider.prompts) == 2
    assert "이전 응답:" in provider.prompts[1]


# 시나리오 6. CLI provider 응답이 schema를 위반하면 ValidationError로 실패한다.
@pytest.mark.unit
def test_cli_provider__invalid_json_schema__raises_validation_error():
    # Given: score 범위를 위반하는 JSON 응답을 반환하는 CLI provider fake를 준비한다.
    invalid_payload = {
        "item_id": "item-1",
        "is_relevant": True,
        "score": 1.4,
        "threshold": 0.7,
        "matched_keywords": ["AI agent"],
        "reason": "AI agent workflow를 직접 다루므로 관심사와 관련이 높다.",
    }
    provider = QueueCliProvider(
        [
            json.dumps(invalid_payload, ensure_ascii=False),
            json.dumps(invalid_payload, ensure_ascii=False),
        ]
    )

    # When / Then: Pydantic 검증 단계에서 score 범위 오류를 발생시킨다.
    with pytest.raises(ValidationError) as error:
        _ = provider.generate_json("judge relevance", RelevanceJudgment)

    assert any(err["loc"] == ("score",) for err in error.value.errors())
