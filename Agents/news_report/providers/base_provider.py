from __future__ import annotations

import json
import re
import subprocess
from abc import ABC, abstractmethod
from typing import TypeVar

from pydantic import BaseModel, ValidationError

from providers.protocols import ProviderOptions


StructuredModel = TypeVar("StructuredModel", bound=BaseModel)


class BaseCliProvider(ABC):
    timeout: int = 120

    @abstractmethod
    def _build_command(self, prompt: str) -> list[str]:
        pass

    def run(self, prompt: str) -> str:
        cmd = self._build_command(prompt)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=self.timeout,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"{self.__class__.__name__} 실행 실패 (exit {result.returncode}): {result.stderr[:200]}"
            )
        return result.stdout.strip()

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        """CLI provider에서 텍스트 응답을 생성한다."""
        _ = options
        return self.run(prompt)

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        """CLI agent 응답을 JSON으로 파싱하고 Pydantic 모델로 검증한다."""
        raw = self.generate_text(
            build_structured_prompt(prompt, schema_model),
            options=options,
        )
        try:
            return validate_json_response(raw, schema_model)
        except (json.JSONDecodeError, ValueError, ValidationError) as error:
            repair_raw = self.generate_text(
                build_json_repair_prompt(raw, schema_model, error),
                options=options,
            )
            return validate_json_response(repair_raw, schema_model)


def build_structured_prompt(prompt: str, schema_model: type[BaseModel]) -> str:
    """CLI agent가 Pydantic schema에 맞는 JSON만 출력하도록 지시문을 붙인다."""
    schema_json = json.dumps(
        schema_model.model_json_schema(),
        ensure_ascii=False,
        indent=2,
    )
    return "\n".join(
        [
            prompt,
            "",
            "응답은 반드시 아래 JSON Schema를 만족하는 JSON object 하나만 출력하세요.",
            "Markdown 코드 블록, 설명 문장, 주석, 추가 텍스트를 포함하지 마세요.",
            "",
            "JSON Schema:",
            schema_json,
        ]
    )


def build_json_repair_prompt(
    raw_response: str,
    schema_model: type[BaseModel],
    error: Exception,
) -> str:
    """잘못된 CLI 응답을 schema에 맞는 JSON object로 다시 출력하게 하는 prompt."""
    schema_json = json.dumps(
        schema_model.model_json_schema(),
        ensure_ascii=False,
        indent=2,
    )
    return "\n".join(
        [
            "이전 응답이 JSON schema 검증에 실패했습니다.",
            "아래 원문 응답의 의미를 유지하되, 반드시 JSON object 하나만 다시 출력하세요.",
            "Markdown 코드 블록, 설명 문장, 주석, 추가 텍스트를 포함하지 마세요.",
            "",
            f"검증 오류: {type(error).__name__}: {str(error)[:500]}",
            "",
            "JSON Schema:",
            schema_json,
            "",
            "이전 응답:",
            raw_response[:8000],
        ]
    )


def validate_json_response(
    raw_response: str,
    schema_model: type[StructuredModel],
) -> StructuredModel:
    """raw 응답에서 JSON object를 추출해 schema model로 검증한다."""
    return schema_model.model_validate(json.loads(extract_json_object(raw_response)))


def extract_json_object(text: str) -> str:
    """CLI agent 출력에서 첫 번째 JSON object 문자열을 추출한다."""
    stripped = text.strip()
    if stripped.startswith("{") and stripped.endswith("}"):
        return stripped

    fenced_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fenced_match:
        return fenced_match.group(1)

    object_match = re.search(r"\{.*\}", text, re.DOTALL)
    if object_match:
        return object_match.group(0)

    raise ValueError("CLI provider 응답에서 JSON object를 찾을 수 없습니다.")
