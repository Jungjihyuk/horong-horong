"""Ollama HTTP API 기반 structured provider 구현체."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping
from typing import Any

from providers.protocols import ProviderOptions, StructuredModel


HttpPost = Callable[[str, Mapping[str, Any], float], Mapping[str, Any]]


class OllamaProvider:
    """Ollama 로컬 서버를 통해 텍스트와 Pydantic JSON 응답을 생성한다."""

    def __init__(
        self,
        model: str = "qwen3:14b",
        endpoint: str = "http://localhost:11434",
        timeout: float = 120,
        think: bool | None = None,
        transport: HttpPost | None = None,
    ):
        self.model = model
        self.endpoint = endpoint.rstrip("/")
        self.timeout = timeout
        # None 이면 `think` 필드를 아예 보내지 않는다 — 기존 동작 그대로다.
        # False 로 주면 추론(thinking)을 끈다. qwen3 계열은 이걸 안 끄면 사고 토큰을
        # 무한정 생성해서, structured output 요청 하나가 분 단위로 늘어지거나 빈 응답으로
        # 끝난다(실측: 끄면 10초, 안 끄면 6분+ 타임아웃).
        self.think = think
        self._transport = transport or self._post_json

    def run(self, prompt: str) -> str:
        """기존 TextProvider 계약과 호환되는 텍스트 생성 메서드."""
        return self.generate_text(prompt)

    def generate_text(
        self,
        prompt: str,
        options: ProviderOptions | None = None,
    ) -> str:
        """Ollama `/api/generate`로 자유 텍스트 응답을 생성한다."""
        response = self._generate(prompt=prompt, options=options)
        return self._extract_response_text(response)

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        """Ollama structured output을 Pydantic 모델로 검증해 반환한다."""
        response = self._generate(
            prompt=prompt,
            options=options,
            response_format=schema_model.model_json_schema(),
        )
        response_text = self._extract_response_text(response)
        parsed = json.loads(response_text)
        return schema_model.model_validate(parsed)

    def _generate(
        self,
        *,
        prompt: str,
        options: ProviderOptions | None,
        response_format: Mapping[str, Any] | None = None,
    ) -> Mapping[str, Any]:
        payload: dict[str, Any] = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
        }
        if self.think is not None:
            payload["think"] = self.think
        ollama_options = self._to_ollama_options(options)
        if ollama_options:
            payload["options"] = ollama_options
        if response_format is not None:
            payload["format"] = response_format

        return self._transport(f"{self.endpoint}/api/generate", payload, self.timeout)

    def _to_ollama_options(self, options: ProviderOptions | None) -> dict[str, Any]:
        if options is None:
            return {}

        values: dict[str, Any] = {}
        if options.temperature is not None:
            values["temperature"] = options.temperature
        if options.num_ctx is not None:
            values["num_ctx"] = options.num_ctx
        if options.top_p is not None:
            values["top_p"] = options.top_p
        return values

    def _extract_response_text(self, response: Mapping[str, Any]) -> str:
        value = response.get("response")
        if not isinstance(value, str):
            raise ValueError("Ollama 응답에 문자열 response 필드가 없습니다.")
        return value.strip()

    def _post_json(
        self,
        url: str,
        payload: Mapping[str, Any],
        timeout: float,
    ) -> Mapping[str, Any]:
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                response_body = response.read().decode("utf-8")
        except urllib.error.URLError as error:
            raise RuntimeError(f"Ollama 요청 실패: {error}") from error

        parsed: Any = json.loads(response_body)
        if not isinstance(parsed, dict):
            raise ValueError("Ollama 응답 JSON이 객체가 아닙니다.")
        return parsed
