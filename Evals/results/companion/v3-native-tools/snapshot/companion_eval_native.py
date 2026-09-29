"""v3 의도 평가를 Ollama 네이티브 tool calling 으로 다시 실행한다.

사례·가짜 저장소·채점 기준·도구 결과 문맥(answer_context)은 `companion_eval.py` 의 v3 를 그대로 쓴다.
바뀌는 것은 판단 방식 하나다. v3 는 모델이 JSON 양식(행동 + 인자)을 채우고, 여기서는 모델이
도구 목록을 보고 부를지·무엇을·어떤 값으로 부를지 정한다. v3 결과의 재현성을 지키려고
`companion_eval.py` 는 고치지 않고 가져다 쓴다.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

from companion_eval import (ANSWER_SYSTEM, CASES, NOW, SEED, FakeTools, annotate_record, answer_context,
                            grade)

EVALUATION_VERSION = "v3-native-tools"

# 도구가 없는 세 행동은 네이티브 방식에서 모두 "도구를 부르지 않음"이 된다. 서로 구분해 채점하지 않는다.
NO_TOOL_ACTIONS = ("conversation", "clarification", "history_recall")

TOOLS = [
    {"type": "function", "function": {
        "name": "schedule_lookup",
        "description": "저장된 일정·할일을 조회한다. 사용자가 일정 조회를 명시적으로 요청할 때만 쓴다.",
        "parameters": {"type": "object", "properties": {
            "date": {"type": "string", "description": "조회할 날짜 YYYY-MM-DD. 바로 다음 일정 하나만 찾을 때는 비운다."},
            "after": {"type": "string", "description": "사용자가 명시한 시간 조건 HH:MM. 말하지 않았으면 비운다. 현재 시각을 넣지 않는다."},
            "next_only": {"type": "boolean", "description": "가장 가까운 다음 일정 하나만 원할 때만 true."}},
            "required": []}}},
    {"type": "function", "function": {
        "name": "schedule_create",
        "description": "할일을 저장한다. 사용자가 추가를 명시적으로 요청할 때만 쓴다.",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string", "description": "저장할 제목."},
            "date": {"type": "string", "description": "날짜 YYYY-MM-DD."},
            "after": {"type": "string", "description": "사용자가 명시한 시간 HH:MM. 말하지 않았으면 비운다. 현재 시각이나 자정을 넣지 않는다."}},
            "required": ["title", "date"]}}},
    {"type": "function", "function": {
        "name": "goal_lookup",
        "description": "앱에 저장된 사용자의 개인 목표를 조회한다. 앞선 대화에서 한 말을 확인할 때는 쓰지 않는다.",
        "parameters": {"type": "object", "properties": {}, "required": []}}},
    {"type": "function", "function": {
        "name": "app_help",
        "description": "앱 기능의 사용법 안내 자료를 조회한다.",
        "parameters": {"type": "object", "properties": {}, "required": []}}},
]

# v3 판단 규칙과 같은 내용을 도구 선택 지시로 옮긴다. 답변 규칙은 v3 를 그대로 붙인다.
SYSTEM = f"""현재 시각 {NOW}, Asia/Seoul. 사용자의 요청에 맞게 도구를 쓰거나 도구 없이 바로 답하세요.
대화 소재만으로 조회/저장을 하지 마세요. 고민·감정·준비 방법 상담은 일정이나 목표가 소재여도 도구 없이 대화로 답합니다.
명시적인 일정 조회 요청에만 schedule_lookup, 명시적인 할일 추가 요청에만 schedule_create를 씁니다.
개인 목표 확인은 goal_lookup, 앱 기능 사용법은 app_help를 씁니다.
앞선 대화에서 사용자가 한 말을 묻는 경우는 도구를 쓰지 말고 대화 기록에서 찾아 답합니다. 저장소 목표를 대신 조회하지 않습니다.
부정과 정정을 최근 맥락으로 이해하고, 저장·변경하지 말라는 정정을 우선 반영하세요.
조회·변경 요청의 대상이나 날짜가 불명확하면 도구를 쓰지 말고 확인 질문을 하세요. 임의의 변경 대상이나 날짜를 추측하지 마세요.
일정 전체 조회는 요청 날짜의 모든 항목을 뜻합니다. 이미 지난 항목도 임의로 제외하지 마세요.
사용자가 가장 가까운 다음 일정 하나를 요청한 경우에만 next_only=true이고 date는 비웁니다.
이 경우 현재 시각 필터는 코드가 적용하므로 after에 현재 시각을 넣지 마세요.
after는 사용자가 명시한 시간 조건에만 사용합니다. 일정 추가에서도 현재 시각이나 자정을 임의로 지정하지 마세요.
date에는 YYYY-MM-DD 날짜만, after에는 HH:MM 시간만 넣습니다.

""" + ANSWER_SYSTEM

SETTINGS = {"think": False, "temperature": 0, "num_predict": 512, "num_ctx": 4096}


def ollama_tools(model, messages, tools=TOOLS):
    body = {"model": model, "messages": messages, "tools": tools, "stream": False, "think": False,
            "keep_alive": "1m", "options": {"temperature": 0, "num_predict": 512, "num_ctx": 4096}}
    req = urllib.request.Request("http://127.0.0.1:11434/api/chat",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        # "does not support tools" 같은 서버 거절 사유를 인프라 오류와 함께 남긴다.
        raise OSError(f"HTTP {exc.code}: {exc.read().decode(errors='replace')}") from exc


def tool_calls_of(message):
    return [{"name": call["function"]["name"], "arguments": call["function"].get("arguments") or {}}
            for call in message.get("tool_calls") or []]


def to_decision(call):
    """도구 호출을 v3 판단 계약 모양으로 옮긴다. 모델이 주지 않은 인자는 v3 규칙대로 비운다."""
    decision = {"action": call["name"], "date": "", "after": "", "title": "", "next_only": False}
    for key in ("date", "after", "title", "next_only"):
        if key in call["arguments"]:
            decision[key] = call["arguments"][key]
    return decision


def run_case(test, model, chat=ollama_tools):
    tools = FakeTools()
    record = {"id": test["id"], "model": model, "provider": "ollama", "decision_mode": "native_tools",
              "evaluation_version": EVALUATION_VERSION, "initial_state": copy.deepcopy(tools.items)}
    start = time.monotonic()
    messages = ([{"role": "system", "content": SYSTEM}] + copy.deepcopy(test["history"])
                + [{"role": "user", "content": test["message"]}])
    record["decision_input"] = copy.deepcopy(messages)
    try:
        raw = chat(model, messages)
        record["raw_decision"] = raw
        calls = tool_calls_of(raw["message"])
        record["tool_calls"] = calls
        if not calls:
            # 도구 없이 바로 답했다. 이 답이 최종 답변이다.
            record["decision"] = {"action": "no_tool"}
            record["answer"] = raw["message"].get("content", "")
        else:
            record["decision"] = to_decision(calls[0])
            followup = [{"role": "assistant", "content": raw["message"].get("content", ""),
                         "tool_calls": raw["message"]["tool_calls"]}]
            for index, call in enumerate(calls):
                # 첫 호출은 사례 ID 로 실행해 v3 채점의 기대 상태(new-<사례 ID>)와 맞춘다.
                request_id = test["id"] if index == 0 else f"{test['id']}-{index}"
                decision = to_decision(call)
                result = tools.execute(decision, request_id)
                context = answer_context(decision, result)
                record.setdefault("answer_contexts", []).append(context)
                followup.append({"role": "tool", "tool_name": call["name"],
                                 "content": json.dumps(context, ensure_ascii=False)})
            answer_input = messages + followup
            record["answer_input"] = answer_input
            answer = chat(model, answer_input)
            record["raw_answer"] = answer
            record["answer"] = answer["message"].get("content", "")
            # 도구는 한 번만 실행한다. 답변 단계에서 또 부르면 실행하지 않고 기록만 남긴다.
            record["extra_tool_calls"] = tool_calls_of(answer["message"])
    except (ValueError, KeyError, TypeError) as exc:
        record["execution_error"] = str(exc)
    except (OSError, TimeoutError) as exc:
        record["infrastructure_error"] = str(exc)
    record.update(final_state=tools.items, events=tools.events, elapsed_seconds=time.monotonic() - start,
                  peak_memory_bytes=None, memory_status="not_measured")
    return record


def grade_native(test, record):
    if record.get("infrastructure_error"):
        return {"intent": None, "execution": None, "answer": "not_run", "error": "infrastructure"}
    calls = record.get("tool_calls") or []
    answer = "review_required" if record.get("answer") else "missing"
    if test["expected_action"] in NO_TOOL_ACTIONS:
        untouched = record["final_state"] == SEED and not record["events"] and not record.get("execution_error")
        return {"intent": not calls, "execution": untouched, "answer": answer}
    if not calls:
        # 형식 오류가 아니라 판단 오류다. 도구를 불러야 할 요청에 도구 없이 답했다.
        return {"intent": False, "execution": False, "answer": answer, "error": "missing_tool_call"}
    # 도구가 필요한 사례는 첫 호출을 v3 판단 계약으로 옮겨 v3 채점기로 본다. 호출은 정확히 하나여야 한다.
    scores = grade(test, {**record, "decision": to_decision(calls[0])})
    scores["intent"] = bool(scores["intent"]) and len(calls) == 1
    scores["answer"] = answer
    return scores


def annotate(test, record):
    """v3 설명을 붙이고, 판정 상태는 네이티브 채점 결과로 바꾼다 (v3 채점기는 '도구 안 부름'을 모른다)."""
    result = annotate_record(test, {**record, "decision": record.get("decision")})
    for key in ("intent", "execution"):
        result["review"][key]["status"] = {True: "pass", False: "fail", None: "not_evaluated"}[record["scores"][key]]
    result["review"]["intent"]["evidence"] = "tool_calls: 기대 도구와 인자를 비교. 도구가 없는 세 행동은 '도구 안 부름'으로 함께 판정"
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="qwen3.5:9b")
    parser.add_argument("--cases", nargs="*", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if set(args.cases) - {test["id"] for test in CASES}:
        parser.error("알 수 없는 사례 ID입니다.")
    # 기존 실행과 섞이거나 아카이브를 덮어쓰지 않도록 새 run 폴더만 허용한다.
    if args.output.exists():
        parser.error("출력 경로가 이미 있습니다. 새로운 run 폴더를 지정하세요.")
    args.output.mkdir(parents=True)
    selected = [test for test in CASES if not args.cases or test["id"] in args.cases]
    here = Path(__file__).parent
    sources = {name: (here / name).read_text() for name in ("companion_eval_native.py", "companion_eval.py")}
    manifest = {"evaluation_version": EVALUATION_VERSION, "decision_mode": "native_tools",
                "base_evaluation_version": "v3-prompt-context", "grader_version": "v2-native",
                "model": args.model, "provider": "ollama", "status": "running", "cases": selected,
                "initial_state": SEED,
                "source_sha256": {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()},
                "system_prompt": SYSTEM, "tools": TOOLS, "settings": SETTINGS, "completed_cases": [],
                "differences_from_v3": ["JSON 양식 대신 Ollama 네이티브 tool calling 으로 판단",
                                        "판단 규칙은 v3 와 같은 내용을 시스템 지시·도구 설명으로 옮김 (문구는 다름)",
                                        "도구 결과는 v3 answer_context 를 tool 메시지로 전달",
                                        "도구 없이 답하면 첫 응답이 최종 답변 (모델 호출 1회)"],
                "limitations": ["도구가 없는 세 행동(대화·되묻기·이전 발언 확인)은 '도구 안 부름'으로 함께 채점",
                                "답변 의미 검토는 별도", "v3 와 사례·채점 기준은 같지만 판단 방식이 달라 문구 차이 영향이 섞임"]}
    for name, text in sources.items():
        (args.output / name).write_text(text)
    manifest_path = args.output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    for test in selected:
        record = run_case(test, args.model)
        record["scores"] = grade_native(test, record)
        record = annotate(test, record)
        (args.output / f"{test['id']}.json").write_text(json.dumps(record, ensure_ascii=False, indent=2))
        print(test["id"], record["scores"], flush=True)
        manifest["completed_cases"].append(test["id"])
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    manifest["status"] = "completed_not_model_approval"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
