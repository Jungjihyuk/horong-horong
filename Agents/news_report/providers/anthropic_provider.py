"""Anthropic API(과금형) provider.

기존 구독 CLI provider 들과 같은 `StructuredProvider` 계약만 만족한다. 그래서
LangGraph 도입 여부와 무관하게 어디서든 갈아끼울 수 있다.

**구독 CLI 와 결정적으로 다른 점**: 호출 한 번이 곧 청구다. 그래서
`supports_slash_preflight = False` 로 preflight 를 막는다 — 파이프라인의 preflight 는
`/usage` 를 «프롬프트로» 보내 한도를 확인하는데(`patterns/pipelines/news_report_v1.py`),
API 상대로는 그게 쓰레기 응답 하나를 그대로 청구하는 요청이 된다.

`anthropic` SDK 는 지연 임포트한다. 이 provider 를 안 쓰는 환경(로컬 ollama만 쓰는
사용자, 테스트)에서 패키지가 없다고 임포트가 깨지면 안 된다.
"""

from __future__ import annotations

from typing import Any

from providers.base_provider import build_json_repair_prompt
from providers.pricing import estimate_cost_usd, load_pricing
from providers.protocols import ProviderOptions, RateLimitError, StructuredModel
from providers.usage import UsageRecord

DEFAULT_MODEL = "claude-opus-5"
DEFAULT_MAX_TOKENS = 16000


class AnthropicApiProvider:
    """Anthropic Messages API 를 쓰는 구조화 출력 provider."""

    # preflight(`/usage` 를 프롬프트로 전송)를 건너뛰게 하는 표식. 과금 사고 방지용이다.
    supports_slash_preflight: bool = False

    def __init__(
        self,
        *,
        model: str = DEFAULT_MODEL,
        api_key: str | None = None,
        timeout: float = 120.0,
        max_tokens: int = DEFAULT_MAX_TOKENS,
        client: Any | None = None,
    ) -> None:
        self.model = model
        self.timeout = timeout
        self.max_tokens = max_tokens
        self._api_key = api_key
        self._client = client
        # traced_provider 와 usage.total_usage_of 가 이 이름들을 읽는다.
        self._last_repair_attempted: bool = False
        self._last_usage: UsageRecord | None = None
        self._run_usage: UsageRecord | None = None

    # ---------- client ----------

    def _ensure_client(self) -> Any:
        if self._client is not None:
            return self._client
        try:
            import anthropic
        except ImportError as error:  # pragma: no cover - 설치 환경에 따라 다름
            raise RuntimeError(
                "anthropic SDK 가 필요합니다. `uv add anthropic` 로 설치하세요."
            ) from error
        if not self._api_key:
            raise ValueError(
                "ANTHROPIC_API_KEY 를 찾지 못했습니다. 환경변수나 "
                "Agents/news_report/.env 에 설정하세요(.env.example 참고)."
            )
        self._client = anthropic.Anthropic(api_key=self._api_key, timeout=self.timeout)
        return self._client

    # ---------- TextProvider ----------

    def run(self, prompt: str) -> str:
        return self.generate_text(prompt)

    def generate_text(self, prompt: str, options: ProviderOptions | None = None) -> str:
        response = self._create(
            lambda client: client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                messages=[{"role": "user", "content": prompt}],
            )
        )
        return "".join(
            block.text for block in response.content if getattr(block, "type", "") == "text"
        )

    # ---------- StructuredProvider ----------

    def generate_json(
        self,
        prompt: str,
        schema_model: type[StructuredModel],
        options: ProviderOptions | None = None,
    ) -> StructuredModel:
        """structured output 으로 schema 를 강제한다.

        `messages.parse` 가 스키마를 서버에서 강제하므로 CLI provider 만큼 자주
        깨지지 않지만, 검증이 실패하면 CLI 쪽과 같은 «한 번만 고쳐 쓰기» 규칙을 따른다.
        재시도 여부를 `_last_repair_attempted` 로 남겨야 trace 비교가 성립한다.
        """
        self._last_repair_attempted = False
        try:
            return self._parse(prompt, schema_model)
        except (RateLimitError, ValueError, RuntimeError):
            raise
        except Exception as error:
            self._last_repair_attempted = True
            repair = build_json_repair_prompt("", schema_model, error)
            return self._parse(f"{prompt}\n\n{repair}", schema_model)

    def _parse(self, prompt: str, schema_model: type[StructuredModel]) -> StructuredModel:
        response = self._create(
            lambda client: client.messages.parse(
                model=self.model,
                max_tokens=self.max_tokens,
                messages=[{"role": "user", "content": prompt}],
                output_format=schema_model,
            )
        )
        return response.parsed_output

    # ---------- 공통 ----------

    def _create(self, call) -> Any:
        client = self._ensure_client()
        try:
            response = call(client)
        except Exception as error:
            raise self._translate(error) from error
        self._record_usage(response)
        return response

    def _translate(self, error: Exception) -> Exception:
        """한도 초과를 파이프라인이 이미 아는 예외로 바꾼다.

        `ontology/service.py` 와 `stages/research_artifacts.py` 가 `RateLimitError` 만
        따로 잡아 실행을 멈추므로, 그 경로에 태워야 동작이 일관된다.
        """
        name = type(error).__name__
        status = getattr(error, "status_code", None)
        if name == "RateLimitError" or status == 429:
            return RateLimitError(f"Anthropic API 사용량 한도 초과: {error}")
        return error

    def _record_usage(self, response: Any) -> None:
        usage = getattr(response, "usage", None)
        if usage is None:
            return

        input_tokens = int(getattr(usage, "input_tokens", 0) or 0)
        output_tokens = int(getattr(usage, "output_tokens", 0) or 0)
        cached = int(getattr(usage, "cache_read_input_tokens", 0) or 0)
        cache_write = int(getattr(usage, "cache_creation_input_tokens", 0) or 0)

        pricing = load_pricing(self.model)
        cost = (
            estimate_cost_usd(
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cached_input_tokens=cached,
                cache_write_input_tokens=cache_write,
                pricing=pricing,
            )
            if pricing
            else None
        )

        record = UsageRecord(
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cached_input_tokens=cached,
            cache_write_input_tokens=cache_write,
            total_cost_usd=cost,
            call_count=1,
        )
        self._last_usage = record
        self._run_usage = (self._run_usage or UsageRecord()).merge(record)
