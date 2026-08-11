"""외부 CLI 기반 TextProvider 구현체 모음."""

from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

from providers.base_provider import BaseCliProvider
from providers.protocols import RateLimitError
from providers.usage import RateLimitSnapshot, UsageRecord


class AntigravityCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["agy", "-p", prompt]


class ClaudeCliProvider(BaseCliProvider):
    """Claude Code CLI 비대화 모드.

    `--output-format json`을 붙이면 stdout이 답변 텍스트가 아니라 JSON object가
    되고, 답변은 `result` 필드로 들어간다. 대신 `usage` 토큰 내역과
    `total_cost_usd`를 함께 얻는다. 구독 잔여 한도는 노출되지 않는다.
    """

    def _build_command(self, prompt: str) -> list[str]:
        return ["claude", "-p", prompt, "--output-format", "json"]

    def parse_output(self, stdout: str) -> tuple[str, UsageRecord | None]:
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError:
            # 예상 밖 출력이면 기존 동작(stdout 전체가 답변)으로 후퇴한다.
            return stdout.strip(), None
        if not isinstance(payload, dict):
            return stdout.strip(), None

        # 파이프라인이 요구하는 구조화 응답 자체가 JSON object라서, 봉투와
        # 답변을 반드시 구분해야 한다. `--output-format json`이 적용되지 않은
        # 경우(구버전 CLI 등) stdout은 답변 JSON 그대로이므로 후퇴시킨다.
        if payload.get("type") != "result":
            return stdout.strip(), None

        text = payload.get("result")
        if payload.get("is_error") or not isinstance(text, str):
            err_msg = str(text or payload.get("subtype") or payload)
            # 에러 문자열을 schema 검증기에 넘기면 무의미한 repair를 유발하고
            # 진짜 원인이 schema 오류로 가려진다. 여기서 바로 실패시킨다.
            lower_err = err_msg.lower()
            if any(k in lower_err for k in ["rate limit", "usage limit", "429", "exceeded"]):
                raise RateLimitError(f"claude 사용량 한도 초과: {err_msg[:200]}")
            raise RuntimeError(f"claude CLI 오류: {err_msg[:200]}")

        usage = payload.get("usage")
        usage = usage if isinstance(usage, dict) else {}
        cost = payload.get("total_cost_usd")
        return text.strip(), UsageRecord(
            input_tokens=_as_int(usage.get("input_tokens")),
            output_tokens=_as_int(usage.get("output_tokens")),
            cached_input_tokens=_as_int(usage.get("cache_read_input_tokens")),
            cache_write_input_tokens=_as_int(usage.get("cache_creation_input_tokens")),
            total_cost_usd=float(cost) if isinstance(cost, (int, float)) else None,
            call_count=1,
        )


class CodexCliProvider(BaseCliProvider):
    """OpenAI Codex CLI 비대화 모드.

    `codex <prompt>` 형태는 대화형 진입이라 stdin TTY 가 없으면
    'stdin is not a terminal' 로 실패한다. `codex exec <prompt>` 가 1회성
    비대화 실행이며 subprocess 환경에서 정상 동작한다. 앱의 뉴스 데이터
    디렉터리는 git 저장소 밖일 수 있으므로 repo 신뢰 검사를 건너뛴다.

    `--json`을 붙이면 stdout이 JSONL 이벤트 스트림이 된다. 답변은
    `item.completed`의 `agent_message` 항목이고 토큰은 `turn.completed`에
    실린다. 요금제 사용률(rate_limits)은 이 스트림에는 없고 세션 rollout
    파일에만 기록되므로 `thread.started`의 thread_id로 따라가 읽는다.
    """

    def _build_command(self, prompt: str) -> list[str]:
        return ["codex", "exec", "--skip-git-repo-check", "--json", prompt]

    def parse_output(self, stdout: str) -> tuple[str, UsageRecord | None]:
        messages: list[str] = []
        usage: UsageRecord | None = None
        thread_id: str | None = None

        for line in stdout.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict):
                continue

            event_type = event.get("type")
            if event_type == "thread.started":
                thread_id = event.get("thread_id")
            elif event_type == "item.completed":
                item = event.get("item")
                # 같은 이벤트로 error 항목도 오므로 agent_message만 취한다.
                if isinstance(item, dict) and item.get("type") == "agent_message":
                    text = item.get("text")
                    if isinstance(text, str):
                        messages.append(text)
            elif event_type == "turn.completed":
                turn_usage = event.get("usage")
                if isinstance(turn_usage, dict):
                    usage = UsageRecord(
                        input_tokens=_as_int(turn_usage.get("input_tokens")),
                        output_tokens=_as_int(turn_usage.get("output_tokens")),
                        cached_input_tokens=_as_int(
                            turn_usage.get("cached_input_tokens")
                        ),
                        cache_write_input_tokens=_as_int(
                            turn_usage.get("cache_write_input_tokens")
                        ),
                        reasoning_output_tokens=_as_int(
                            turn_usage.get("reasoning_output_tokens")
                        ),
                        call_count=1,
                    )

        if not messages:
            lower_stdout = stdout.lower()
            if any(k in lower_stdout for k in ["rate limit", "usage limit", "429", "exceeded"]):
                raise RateLimitError(f"codex 사용량 한도 초과: {stdout[:200]}")
            # JSONL 파싱에 실패했으면 기존 동작으로 후퇴한다.
            return stdout.strip(), usage

        if usage is not None and thread_id:
            limits = _read_codex_rate_limits(thread_id)
            if limits:
                # rate_limits_first는 비워 둔다. 실행 전체의 최초 관측치는
                # UsageRecord.merge가 첫 호출의 rate_limits를 승격시켜 채운다.
                usage = replace(usage, rate_limits=limits)

        return "\n".join(messages).strip(), usage


class OpencodeCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["opencode", "run", prompt]


class HermesCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["hermes", "chat", "send", prompt]


def _as_int(value: object) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def _read_codex_rate_limits(thread_id: str) -> tuple[RateLimitSnapshot, ...]:
    """codex 세션 rollout 파일에서 가장 최근 rate_limits 스냅샷을 읽는다.

    한도 정보는 부가 기능이므로 어떤 실패도 리포트 생성을 막지 않는다.
    """
    try:
        sessions_root = Path.home() / ".codex" / "sessions"
        matches = sorted(sessions_root.rglob(f"rollout-*{thread_id}.jsonl"))
        if not matches:
            return ()
        lines = matches[-1].read_text(encoding="utf-8").splitlines()
    except OSError:
        return ()

    for line in reversed(lines):
        if '"rate_limits"' not in line:
            continue
        try:
            payload = json.loads(line).get("payload")
        except (json.JSONDecodeError, AttributeError):
            continue
        if not isinstance(payload, dict):
            continue
        limits = payload.get("rate_limits")
        if not isinstance(limits, dict):
            continue

        plan_type = limits.get("plan_type")
        snapshots: list[RateLimitSnapshot] = []
        # 요금제에 따라 secondary가 없을 수 있다 (free는 primary만 존재).
        for scope in ("primary", "secondary"):
            window = limits.get(scope)
            if not isinstance(window, dict):
                continue
            used = window.get("used_percent")
            snapshots.append(
                RateLimitSnapshot(
                    scope=scope,
                    used_percent=(
                        float(used) if isinstance(used, (int, float)) else None
                    ),
                    window_minutes=_as_int(window.get("window_minutes")) or None,
                    resets_at=_as_int(window.get("resets_at")) or None,
                    plan_type=plan_type if isinstance(plan_type, str) else None,
                )
            )
        return tuple(snapshots)

    return ()
