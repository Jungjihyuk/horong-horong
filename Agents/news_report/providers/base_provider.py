from __future__ import annotations

import json
import re
import subprocess
from abc import ABC, abstractmethod
from typing import TypeVar

from pydantic import BaseModel, ValidationError

from providers.protocols import ProviderOptions
from providers.usage import UsageRecord


StructuredModel = TypeVar("StructuredModel", bound=BaseModel)


class BaseCliProvider(ABC):
    # source insight처럼 본문이 긴 구조화 출력 호출은 120s를 넘길 수 있다 (#83).
    # request providerOptions.timeout으로 재정의할 수 있다 (factory에서 주입).
    timeout: float = 300

    # 직전 generate_json 호출에서 repair(검증 실패 후 재생성)가 발생했는지를 노출한다.
    # TracedStructuredProvider(envelope)가 호출 직후 이 값을 읽어 trace payload에 싣는다.
    # 주의: 호출 사이에 유지되는 상태라 순차 호출(현재 파이프라인 구조)에서만 정확하다.
    _last_repair_attempted: bool = False

    # 직전 generate_json 호출에서 누적된 토큰/비용 소모량. repair가 발생하면
    # 두 호출이 합산된다. usage를 보고하지 않는 CLI는 None으로 남는다.
    # TracedStructuredProvider가 호출 직후 읽어 trace payload에 싣는다.
    _last_usage: UsageRecord | None = None

    # 이 provider 인스턴스로 수행한 모든 호출의 누적 소모량. reset하지 않는다.
    # TracedStructuredProvider는 trace가 있을 때만 감싸이고 ontology 단계는
    # 그 wrapper를 우회하므로, 누적은 wrapper가 아니라 여기서 해야 빠짐이 없다.
    _run_usage: UsageRecord | None = None

    @abstractmethod
    def _build_command(self, prompt: str) -> list[str]:
        pass

    def parse_output(self, stdout: str) -> tuple[str, UsageRecord | None]:
        """CLI stdout에서 (답변 텍스트, 소모량)을 분리한다.

        기본값은 stdout 전체가 답변이고 소모량은 알 수 없는 경우다.
        usage를 보고하는 CLI(claude/codex)만 재정의한다.
        """
        return stdout.strip(), None

    def run(self, prompt: str) -> str:
        cmd = self._build_command(prompt)
        try:
            result = self._run_subprocess(cmd)
        except subprocess.TimeoutExpired:
            # CLI agent가 네트워크/API 스톨로 간헐적으로 멈출 수 있다 (#83).
            # 동일 작업의 정상 호출은 timeout보다 훨씬 짧으므로 1회만 재시도한다.
            result = self._run_subprocess(cmd)
        if result.returncode != 0:
            err_msg = result.stderr[:200]
            lower_err = err_msg.lower()
            if any(k in lower_err for k in ["rate limit", "usage limit", "429", "exceeded"]):
                from providers.protocols import RateLimitError
                raise RateLimitError(f"{self.__class__.__name__} 사용량 한도 초과: {err_msg}")
            raise RuntimeError(
                f"{self.__class__.__name__} 실행 실패 (exit {result.returncode}): {err_msg}"
            )
        text, usage = self.parse_output(result.stdout)
        if usage is not None:
            # repair 재시도가 있으면 두 호출의 소모량을 합산한다.
            self._last_usage = (self._last_usage or UsageRecord()).merge(usage)
            self._run_usage = (self._run_usage or UsageRecord()).merge(usage)
        return text

    def _run_subprocess(self, cmd: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=self.timeout,
        )

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
        self._last_repair_attempted = False
        self._last_usage = None
        raw = self.generate_text(
            build_structured_prompt(prompt, schema_model),
            options=options,
        )
        try:
            return validate_json_response(raw, schema_model)
        except (json.JSONDecodeError, ValueError, ValidationError) as error:
            self._last_repair_attempted = True
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
