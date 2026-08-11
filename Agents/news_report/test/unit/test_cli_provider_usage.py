"""CLI provider 소모량(usage) 파싱 단위 테스트.

fixture는 실제 `claude -p --output-format json` / `codex exec --json` 출력을
그대로 옮긴 것이다. 필드 이름을 추측하지 않기 위해 실측값을 유지한다.
"""

import json
from pathlib import Path

import pytest

from providers import cli_providers
from providers.cli_providers import ClaudeCliProvider, CodexCliProvider
from providers.usage import RateLimitSnapshot, UsageRecord


# 실제 `claude -p "reply with exactly: PONG" --output-format json` 응답 (발췌).
_CLAUDE_STDOUT = json.dumps(
    {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "result": "PONG",
        "session_id": "f175fb43-a668-4fb1-8629-257aeb37b8cb",
        "total_cost_usd": 0.216895,
        "usage": {
            "input_tokens": 2,
            "cache_creation_input_tokens": 21276,
            "cache_read_input_tokens": 8050,
            "output_tokens": 4,
        },
    }
)

# 실제 `codex exec --skip-git-repo-check --json "..."` 스트림.
# item.completed로 error 항목이 함께 오는 점이 중요하다.
_CODEX_STDOUT = "\n".join(
    [
        json.dumps({"type": "thread.started", "thread_id": "019ff0ad-fcd9-7243"}),
        json.dumps(
            {
                "type": "item.completed",
                "item": {"id": "item_0", "type": "error", "message": "service tier..."},
            }
        ),
        json.dumps({"type": "turn.started"}),
        json.dumps(
            {
                "type": "item.completed",
                "item": {"id": "item_1", "type": "agent_message", "text": "PONG"},
            }
        ),
        json.dumps(
            {
                "type": "turn.completed",
                "usage": {
                    "input_tokens": 17253,
                    "cached_input_tokens": 4480,
                    "cache_write_input_tokens": 0,
                    "output_tokens": 23,
                    "reasoning_output_tokens": 15,
                },
            }
        ),
    ]
)


# 시나리오 1. claude JSON 출력에서 답변은 result 필드에서, 소모량은 usage에서 나온다.
@pytest.mark.unit
def test_claude_parse_output__json_response__returns_result_and_usage():
    # Given: 실제 claude --output-format json 응답을 준비한다.
    provider = ClaudeCliProvider()

    # When: stdout을 파싱한다.
    text, usage = provider.parse_output(_CLAUDE_STDOUT)

    # Then: stdout 전체가 아니라 result 필드가 답변으로 반환된다.
    assert text == "PONG"
    assert usage is not None
    assert usage.input_tokens == 2
    assert usage.output_tokens == 4
    assert usage.cached_input_tokens == 8050
    assert usage.cache_write_input_tokens == 21276
    assert usage.total_cost_usd == pytest.approx(0.216895)
    # claude는 구독 잔여 한도를 노출하지 않는다.
    assert usage.rate_limits == ()


# 시나리오 2. claude가 오류를 보고하면 schema 검증기로 넘기지 않고 바로 실패한다.
@pytest.mark.unit
def test_claude_parse_output__error_response__raises_runtime_error():
    # Given: is_error가 true인 응답을 준비한다.
    provider = ClaudeCliProvider()
    stdout = json.dumps(
        {"type": "result", "is_error": True, "result": "Credit balance too low"}
    )

    # When / Then: 오류 문자열이 답변으로 흘러가지 않고 RuntimeError로 실패한다.
    with pytest.raises(RuntimeError, match="claude CLI 오류"):
        _ = provider.parse_output(stdout)


# 시나리오 3. 봉투가 아닌 구조화 답변 JSON은 답변 그대로 통과시킨다.
# 파이프라인이 모델에게 요구하는 응답이 바로 이 형태라, 봉투로 오인하면
# 정상 응답이 CLI 오류로 둔갑한다.
@pytest.mark.unit
@pytest.mark.parametrize(
    "stdout",
    [
        '  {"score": 1}  ',  # --output-format json 미적용(구버전 CLI 등)
        '{"result": "요약", "score": 1}',  # 답변이 우연히 result 키를 가진 경우
        "설명 문장 응답",  # JSON이 아닌 평문
    ],
)
def test_claude_parse_output__not_an_envelope__falls_back_to_raw_text(stdout: str):
    # Given: type이 "result"가 아닌, 즉 봉투가 아닌 출력을 준비한다.
    provider = ClaudeCliProvider()

    # When: stdout을 파싱한다.
    text, usage = provider.parse_output(stdout)

    # Then: 원문이 그대로 답변이 되고 소모량은 알 수 없다.
    assert text == stdout.strip()
    assert usage is None


# 시나리오 4. codex JSONL에서 agent_message만 답변으로 취하고 error 항목은 무시한다.
@pytest.mark.unit
def test_codex_parse_output__jsonl_stream__returns_agent_message_and_usage(monkeypatch):
    # Given: rollout 파일이 없는 환경에서 실제 codex --json 스트림을 준비한다.
    monkeypatch.setattr(cli_providers.Path, "home", staticmethod(lambda: Path("/nonexistent")))
    provider = CodexCliProvider()

    # When: stdout을 파싱한다.
    text, usage = provider.parse_output(_CODEX_STDOUT)

    # Then: error 항목은 제외되고 agent_message만 답변이 된다.
    assert text == "PONG"
    assert usage is not None
    assert usage.input_tokens == 17253
    assert usage.output_tokens == 23
    assert usage.cached_input_tokens == 4480
    assert usage.reasoning_output_tokens == 15


# 시나리오 5. codex JSONL 파싱에 실패하면 기존 동작으로 후퇴한다.
@pytest.mark.unit
def test_codex_parse_output__no_agent_message__falls_back_to_raw_text():
    # Given: agent_message가 없는 평문 출력을 준비한다.
    provider = CodexCliProvider()

    # When: stdout을 파싱한다.
    text, usage = provider.parse_output("plain text answer")

    # Then: 평문이 그대로 답변이 된다.
    assert text == "plain text answer"
    assert usage is None


# 시나리오 6. codex 요금제 사용률은 세션 rollout 파일에서 읽어 usage에 실린다.
@pytest.mark.unit
def test_codex_parse_output__rollout_file__attaches_rate_limits(monkeypatch, tmp_path):
    # Given: thread_id에 대응하는 rollout 파일에 rate_limits 스냅샷을 심는다.
    sessions = tmp_path / ".codex" / "sessions" / "2026" / "08" / "11"
    sessions.mkdir(parents=True)
    rollout = sessions / "rollout-2026-08-11T20-56-02-019ff0ad-fcd9-7243.jsonl"
    _ = rollout.write_text(
        json.dumps(
            {
                "timestamp": "2026-08-11T20:56:02Z",
                "type": "turn_context",
                "payload": {
                    "rate_limits": {
                        "primary": {
                            "used_percent": 5.0,
                            "window_minutes": 300,
                            "resets_at": 1782152190,
                        },
                        "secondary": {
                            "used_percent": 7.0,
                            "window_minutes": 10080,
                            "resets_at": 1782360962,
                        },
                        "plan_type": "pro",
                    }
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(cli_providers.Path, "home", staticmethod(lambda: tmp_path))
    provider = CodexCliProvider()

    # When: stdout을 파싱한다.
    _, usage = provider.parse_output(_CODEX_STDOUT)

    # Then: primary/secondary 사용률이 window_minutes와 함께 실린다.
    assert usage is not None
    assert len(usage.rate_limits) == 2
    primary, secondary = usage.rate_limits
    assert (primary.scope, primary.used_percent, primary.window_minutes) == (
        "primary",
        5.0,
        300,
    )
    assert (secondary.scope, secondary.used_percent, secondary.window_minutes) == (
        "secondary",
        7.0,
        10080,
    )
    assert primary.plan_type == "pro"


# 시나리오 7. free 요금제처럼 secondary가 없어도 primary만으로 파싱된다.
@pytest.mark.unit
def test_codex_parse_output__free_plan_without_secondary__parses_primary_only(
    monkeypatch, tmp_path
):
    # Given: secondary가 null이고 window가 30일인 free 요금제 rollout을 준비한다.
    sessions = tmp_path / ".codex" / "sessions"
    sessions.mkdir(parents=True)
    _ = (sessions / "rollout-x-019ff0ad-fcd9-7243.jsonl").write_text(
        json.dumps(
            {
                "payload": {
                    "rate_limits": {
                        "primary": {"used_percent": 0.0, "window_minutes": 43200},
                        "secondary": None,
                        "plan_type": "free",
                    }
                }
            }
        )
        + "\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(cli_providers.Path, "home", staticmethod(lambda: tmp_path))
    provider = CodexCliProvider()

    # When: stdout을 파싱한다.
    _, usage = provider.parse_output(_CODEX_STDOUT)

    # Then: primary 스냅샷만 만들어지고 창 길이는 요금제 값을 그대로 따른다.
    assert usage is not None
    assert len(usage.rate_limits) == 1
    assert usage.rate_limits[0].window_minutes == 43200
    assert usage.rate_limits[0].plan_type == "free"


# 시나리오 8. 소모량 누적은 토큰/비용을 더하고 한도 스냅샷은 최신 값으로 대체한다.
@pytest.mark.unit
def test_usage_record_merge__two_calls__adds_tokens_and_replaces_snapshot():
    # Given: repair 재시도처럼 두 번의 호출 소모량을 준비한다.
    first = UsageRecord(
        input_tokens=100,
        output_tokens=10,
        total_cost_usd=0.5,
        rate_limits=(RateLimitSnapshot(scope="primary", used_percent=1.0),),
    )
    second = UsageRecord(
        input_tokens=200,
        output_tokens=20,
        total_cost_usd=0.25,
        rate_limits=(RateLimitSnapshot(scope="primary", used_percent=3.0),),
    )

    # When: 두 호출을 누적한다.
    merged = first.merge(second)

    # Then: 토큰과 비용은 합산되고 사용률은 시점 스냅샷이라 최신 값만 남는다.
    assert merged.input_tokens == 300
    assert merged.output_tokens == 30
    assert merged.total_cost_usd == pytest.approx(0.75)
    assert merged.rate_limits[0].used_percent == 3.0


# 시나리오 8-1. 사용률은 누적 절대값이라 최초 관측치를 따로 보존해야
# "이번 실행으로 몇 % 썼는지"를 계산할 수 있다.
@pytest.mark.unit
def test_usage_record_merge__three_calls__keeps_first_and_last_snapshot():
    # Given: 실행 중 사용률이 1% → 3% → 6%로 올라간 세 번의 호출을 준비한다.
    def call(percent: float) -> UsageRecord:
        return UsageRecord(
            call_count=1,
            rate_limits=(RateLimitSnapshot(scope="primary", used_percent=percent),),
        )

    # When: 실행 전체로 누적한다.
    total = UsageRecord().merge(call(1.0)).merge(call(3.0)).merge(call(6.0))

    # Then: 최초/최종 관측이 모두 남아 차감량(6 - 1 = 5%)을 계산할 수 있다.
    assert total.call_count == 3
    assert total.rate_limits_first[0].used_percent == 1.0
    assert total.rate_limits[0].used_percent == 6.0


# 시나리오 9. 소모량을 보고하지 않는 provider는 usage가 None으로 남는다.
@pytest.mark.unit
def test_usage_record_merge__none__keeps_original():
    # Given: 기존 누적값을 준비한다.
    original = UsageRecord(input_tokens=5)

    # When: usage를 보고하지 않는 호출을 누적한다.
    merged = original.merge(None)

    # Then: 원래 값이 유지된다.
    assert merged == original
