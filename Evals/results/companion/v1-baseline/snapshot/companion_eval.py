"""제품과 분리한 로컬 의도/실행 평가. 실제 사용자 저장소에는 접근하지 않는다."""
from __future__ import annotations

import argparse
import copy
import json
import time
import urllib.request
from pathlib import Path

NOW = "2026-09-18T10:00:00+09:00"
SEED = [
    {"id": "t1", "title": "팀 회의", "date": "2026-09-18", "time": "09:00"},
    {"id": "t2", "title": "배포 점검", "date": "2026-09-18", "time": "15:00"},
    {"id": "t3", "title": "면접 준비", "date": "2026-09-19", "time": "11:00"},
    {"id": "t4", "title": "이력서 첨삭", "date": "2026-09-25", "time": "14:00"},
]
ACTIONS = ["conversation", "clarification", "schedule_lookup", "schedule_create",
           "goal_lookup", "app_help", "history_recall"]
SCHEMA = {"type": "object", "additionalProperties": False,
          "properties": {"action": {"type": "string", "enum": ACTIONS},
                         "date": {"type": "string"}, "after": {"type": "string"},
                         "title": {"type": "string"}, "next_only": {"type": "boolean"}},
          "required": ["action", "date", "after", "title", "next_only"]}
SYSTEM = f"""사용자의 요청 행동을 판단하세요. 현재 시각 {NOW}, Asia/Seoul.
대화 소재만으로 조회/저장을 하지 마세요. 고민과 조언은 conversation,
개인 목표 확인은 goal_lookup, 앱 기능 사용법은 app_help,
앞선 발언 확인은 history_recall입니다. 부정과 정정을 최근 맥락으로 이해하세요.
명시적 일정 조회는 schedule_lookup, 명시적 할일 추가는 schedule_create.
불명확한 변경 요청은 clarification. 임의의 변경 대상이나 날짜를 추측하지 마세요.
date는 YYYY-MM-DD, after는 HH:MM, title은 저장할 제목입니다.
사용하지 않는 문자열은 빈 문자열, next_only는 바로 다음 일정 조회일 때만 true.
next_only일 때 날짜 미지정은 빈 date로 전체 미래 일정에서 찾습니다.
JSON으로만 출력하세요."""


def case(key, message, action, *, expected=None, ids=None, history=None):
    return {"id": key, "message": message, "expected_action": action,
            "expected_args": expected or {}, "expected_ids": ids,
            "history": history or []}


CASES = [
    case("worry", "다음주에 이력서 첨삭 일정이 있는데 어떻게 준비해야 할지 모르겠네", "conversation"),
    case("correction", "아니 일정을 추가해달라는게 아니고 고민이라고", "conversation", history=[
        {"role": "user", "content": "다음주 첨삭 일정 때문에 걱정이야"},
        {"role": "assistant", "content": "날짜와 시간을 더 구체적으로 알려주세요."}]),
    case("goal", "내 목표가 뭔지 아니", "goal_lookup"),
    case("help", "목표 기능은 어떻게 써?", "app_help"),
    case("tomorrow", "내일 일정 보여줘", "schedule_lookup", expected={"date": "2026-09-19"}, ids=["t3"]),
    case("today", "오늘 할일 보여줘", "schedule_lookup", expected={"date": "2026-09-18"}, ids=["t1", "t2"]),
    case("date", "9월 25일 일정 알려줘", "schedule_lookup", expected={"date": "2026-09-25"}, ids=["t4"]),
    case("after", "오늘 오후 2시 이후 일정 보여줘", "schedule_lookup", expected={"date": "2026-09-18", "after": "14:00"}, ids=["t2"]),
    case("next", "지금 바로 다음 일정은 뭐야?", "schedule_lookup", expected={"next_only": True}, ids=["t2"]),
    case("create", "오늘 할일에 호롱호롱 앱 배포하기 추가해줘", "schedule_create", expected={"date": "2026-09-18", "title": "호롱호롱 앱 배포하기"}),
    case("negation", "내일 일정을 추가하지 마. 그냥 걱정돼서 말한 거야", "conversation"),
    case("ambiguous", "그거 금요일로 옮겨줘", "clarification"),
    case("greeting", "오늘 좀 지치네. 잠깐 이야기할래?", "conversation"),
    case("recall", "아까 내가 목표라고 말한 게 뭐였지?", "history_recall", history=[
        {"role": "user", "content": "내 목표는 이번 달에 포트폴리오 완성이야."},
        {"role": "assistant", "content": "포트폴리오 완성이 목표시군요."}]),
    case("empty", "9월 20일 일정 보여줘", "schedule_lookup", expected={"date": "2026-09-20"}, ids=[]),
]


# 채점 설명은 모델 프롬프트와 분리한다. 답변 예문과의 문구 일치를 요구하지 않는다.
CASE_DESCRIPTIONS = {
    "worry": ("예정된 이력서 첨삭을 앞두고 준비에 대한 고민을 말한다.", "고민을 이해하고 준비 방법을 함께 정리한다.", "일정 등록용 날짜·시간을 요구하거나 저장했다고 말하지 않는다."),
    "correction": ("앞선 일정 오해를 사용자가 명시적으로 정정한다.", "정정을 받아들이고 고민 상담으로 돌아간다.", "일정 키워드 때문에 다시 조회·등록 안내를 반복하지 않는다."),
    "goal": ("앱에 저장된 개인 목표를 묻는다.", "저장된 목표인 이번 달 포트폴리오 완성을 근거로 답한다.", "개인 목표 대신 앱 기능 설명을 하거나 목표를 지어내지 않는다."),
    "help": ("개인 목표 내용이 아니라 목표 기능 사용법을 묻는다.", "앱 사용 안내를 근거로 설명한다.", "개인 목표 조회로 바꾸거나 설명서에 없는 기능을 만들어내지 않는다."),
    "tomorrow": ("고정된 현재 날짜의 다음 날 일정을 요청한다.", "2026-09-19 11:00 면접 준비만 안내한다.", "오늘 또는 다른 날짜의 일정을 내일 일정으로 안내하지 않는다."),
    "today": ("오늘의 전체 할일을 요청한다.", "2026-09-18 팀 회의와 배포 점검을 안내한다.", "다른 날짜의 일정을 섞거나 이미 지난 오늘 오전 일정을 임의로 누락하지 않는다."),
    "date": ("월일로 특정 날짜를 지정한다.", "2026-09-25 14:00 이력서 첨삭만 안내한다.", "오늘 일정으로 대체하거나 다른 날짜를 안내하지 않는다."),
    "after": ("오늘 일정 중 오후 2시 이후만 요청한다.", "2026-09-18 15:00 배포 점검만 안내한다.", "오후 2시 이전 일정이나 다른 날짜의 일정을 포함하지 않는다."),
    "next": ("현재 시각 이후 바로 다음 일정 하나를 요청한다.", "현재 10:00 기준 다음인 오늘 15:00 배포 점검 하나만 안내한다.", "지난 09:00 회의나 전체 일정 목록을 다음 일정으로 답하지 않는다."),
    "create": ("시간을 지정하지 않고 오늘 할일 추가를 요청한다.", "오늘 호롱호롱 앱 배포하기를 시간 미지정으로 한 번 저장하고 결과를 알린다.", "00:00 등 시간을 임의로 지정하거나 저장 실패를 성공이라고 말하지 않는다."),
    "negation": ("일정 추가를 명시적으로 금지하며 걱정을 털어놓는다.", "저장하지 않고 걱정에 대해 대화한다.", "부정을 무시해 저장하거나 저장했다고 답하지 않는다."),
    "ambiguous": ("대상과 구체 날짜가 불명확한 이동 요청이다.", "무엇을 어느 금요일로 옮길지 확인한다.", "대상이나 날짜를 추측해 변경하거나 변경 완료라고 말하지 않는다."),
    "greeting": ("피곤함을 말하며 일상 대화를 요청한다.", "상태를 공감하고 자연스럽게 대화를 이어간다.", "오늘이라는 표현만으로 일정 조회·등록 안내로 전환하지 않는다."),
    "recall": ("앞선 대화에서 직접 말한 목표를 다시 묻는다.", "대화 기록의 이번 달 포트폴리오 완성을 기억해 답한다.", "앱 사용법으로 대신하거나 이전에 하지 않은 말을 지어내지 않는다."),
    "empty": ("일정이 없는 특정 날짜를 조회한다.", "2026-09-20에는 등록된 일정이 없다고 안내한다.", "다른 날짜 일정을 대신 보여주거나 없는 일정을 만들어내지 않는다."),
}


def annotate_record(test, record, *, backfilled=False):
    """원시 실행 증거를 보존하면서 사람이 읽을 평가 계약을 덧붙인다."""
    result = copy.deepcopy(record)
    situation, expected_answer, forbidden_answer = CASE_DESCRIPTIONS[test["id"]]
    action = test["expected_action"]
    if action == "schedule_create":
        expected_execution = "요청한 할일 하나만 시간 미지정으로 추가하고 기존 데이터는 유지한다."
        forbidden_execution = "중복 저장, 임의 시간 지정, 기존 일정 수정·삭제."
    elif action in ("conversation", "clarification", "history_recall"):
        expected_execution = "조회·저장 도구를 실행하지 않고 데이터를 유지한다."
        forbidden_execution = "요청하지 않은 조회·저장·수정·삭제."
    else:
        expected_execution = "요청한 날짜·범위 또는 정보 출처의 결과만 조회하고 데이터를 유지한다."
        forbidden_execution = "범위 밖 일정이나 잘못된 출처 조회, 저장·수정·삭제."
    result["case_description"] = {
        "situation": situation, "user_utterance": test["message"],
        "history": copy.deepcopy(test["history"]), "reference_time": NOW,
        "expected_behavior": {"intent": action, "arguments": copy.deepcopy(test["expected_args"]),
                              "result_ids": test["expected_ids"], "execution": expected_execution,
                              "answer": expected_answer},
        "forbidden_behavior": {"execution": forbidden_execution, "answer": forbidden_answer},
    }
    scores = grade(test, record)
    result["review"] = {
        "intent": {"status": {True: "pass", False: "fail", None: "not_evaluated"}[scores["intent"]],
                   "evidence": "decision: 기대 행동과 명시된 인자를 비교"},
        "execution": {"status": {True: "pass", False: "fail", None: "not_evaluated"}[scores["execution"]],
                      "evidence": "final_state 및 events: 기대 결과와 금지 부수 효과를 묶어 검사",
                      "note": "실패는 실행 계약 중 하나 이상 위반이며 모든 금지 행동을 했다는 뜻은 아니다."},
        "answer": {"status": "review_required" if record.get("answer") else "not_available",
                   "evidence": "answer를 기대·금지 답변 조건과 의미적으로 비교해야 함",
                   "note": "자동 의미 검사는 하지 않으며 표현이 달라도 같은 의미면 허용한다."},
    }
    result["annotation"] = {"version": 1, "backfilled": backfilled,
                            "note": "평가 설명 추가이며 모델 재실행이나 원시 응답 변경이 아님" if backfilled else "실행 후 평가 설명 추가"}
    return result


def validate(value):
    if not isinstance(value, dict) or set(value) != set(SCHEMA["required"]):
        raise ValueError("invalid fields")
    if value["action"] not in ACTIONS or type(value["next_only"]) is not bool:
        raise ValueError("invalid action or boolean")
    from datetime import date, time as clock_time
    for key in ("date", "after", "title"):
        if not isinstance(value[key], str):
            raise ValueError("invalid string")
    if value["date"]:
        if date.fromisoformat(value["date"]).isoformat() != value["date"]:
            raise ValueError("date must be YYYY-MM-DD")
    if value["after"]:
        parsed = clock_time.fromisoformat(value["after"])
        if len(value["after"]) != 5 or parsed.isoformat(timespec="minutes") != value["after"]:
            raise ValueError("time must be HH:MM")
    if value["action"] == "schedule_create" and (not value["date"] or not value["title"].strip()):
        raise ValueError("missing create argument")
    if value["action"] == "schedule_lookup" and not value["date"] and not value["next_only"]:
        raise ValueError("missing lookup date")
    return value


class FakeTools:
    def __init__(self):
        self.items = copy.deepcopy(SEED)
        self.events = []
        self.completed = {}

    def execute(self, decision, request_id):
        d = validate(decision)
        if request_id in self.completed:
            return self.completed[request_id]
        action = d["action"]
        result = None
        if action == "schedule_lookup":
            result = [x for x in self.items if (not d["date"] or x["date"] == d["date"])
                      and (not d["after"] or x["time"] >= d["after"])]
            result.sort(key=lambda x: (x["date"], x["time"], x["id"]))
            if d["next_only"]:
                result = [x for x in result if x["date"] + "T" + x["time"] >= NOW[:16]][:1]
        elif action == "schedule_create":
            result = {"id": f"new-{request_id}", "title": d["title"], "date": d["date"], "time": d["after"]}
            self.items.append(result)
        elif action == "goal_lookup":
            result = {"source": "saved_goals", "goals": ["이번 달 포트폴리오 완성"]}
        elif action == "app_help":
            result = {"source": "app_guide", "text": "메뉴바 팝오버의 성취에서 목표를 관리합니다."}
        if result is not None:
            self.events.append({"action": action, "arguments": copy.deepcopy(d), "result": copy.deepcopy(result)})
        self.completed[request_id] = copy.deepcopy(result)
        return result


def grade(test, record):
    # 모델이 쓴 '성공' 문구가 아니라 판단 계약과 관찰된 상태를 비교한다.
    if record.get("infrastructure_error"):
        return {"intent": None, "execution": None, "answer": "not_run", "error": "infrastructure"}
    d = record.get("decision")
    try:
        validate(d)
    except (ValueError, TypeError, KeyError):
        return {"intent": False, "execution": False, "answer": "not_run", "error": "invalid_output"}
    intent = d["action"] == test["expected_action"] and all(d.get(k) == v for k, v in test["expected_args"].items())
    final = record["final_state"]
    expected_state = copy.deepcopy(SEED)
    if test["expected_action"] == "schedule_create":
        expected_state.append({"id": f"new-{test['id']}", "title": test["expected_args"]["title"],
                               "date": test["expected_args"]["date"], "time": ""})
    execution = final == expected_state and not record.get("execution_error")
    events = record["events"]
    if test["expected_ids"] is not None:
        execution &= len(events) == 1 and events[0]["action"] == "schedule_lookup"
        if execution:
            execution &= [x["id"] for x in events[0]["result"]] == test["expected_ids"]
    elif test["expected_action"] in ("conversation", "clarification", "history_recall"):
        execution &= not events
    elif test["expected_action"] in ("goal_lookup", "app_help"):
        source = "saved_goals" if test["expected_action"] == "goal_lookup" else "app_guide"
        execution &= len(events) == 1 and events[0]["result"].get("source") == source
    return {"intent": bool(intent), "execution": bool(execution),
            "answer": "review_required" if record.get("answer") else "missing"}


def ollama(model, messages, schema=None):
    body = {"model": model, "messages": messages, "stream": False, "think": False,
            "keep_alive": "1m", "options": {"temperature": 0, "num_predict": 512, "num_ctx": 4096}}
    if schema:
        body["format"] = schema
    req = urllib.request.Request("http://127.0.0.1:11434/api/chat",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as response:
        return json.load(response)


def run_case(test, model, chat=ollama):
    tools = FakeTools()
    record = {"id": test["id"], "model": model, "provider": "ollama", "initial_state": copy.deepcopy(tools.items)}
    start = time.monotonic()
    history = copy.deepcopy(test["history"])
    messages = [{"role": "system", "content": SYSTEM}] + history + [{"role": "user", "content": test["message"]}]
    record["decision_input"] = copy.deepcopy(messages)
    try:
        raw = chat(model, messages, SCHEMA)
        record["raw_decision"] = raw
        d = json.loads(raw["message"]["content"])
        record["decision"] = d
        result = tools.execute(d, test["id"])
        answer_input = [{"role": "system", "content": "존댓말로 사용자를 도우세요. 제공된 실제 도구 결과만 사실로 사용하고, 실행하지 않은 저장을 했다고 말하지 마세요."}] + history + [
            {"role": "user", "content": test["message"] + "\n앱 처리 결과: " + json.dumps({"action": d["action"], "result": result}, ensure_ascii=False)}]
        record["answer_input"] = answer_input
        answer = chat(model, answer_input)
        record["raw_answer"] = answer
        record["answer"] = answer["message"]["content"]
    except (ValueError, KeyError, TypeError) as exc:
        record["execution_error"] = str(exc)
    except (OSError, TimeoutError) as exc:
        record["infrastructure_error"] = str(exc)
    record.update(final_state=tools.items, events=tools.events, elapsed_seconds=time.monotonic() - start,
                  peak_memory_bytes=None, memory_status="not_measured")
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="qwen3.5:9b")
    parser.add_argument("--cases", nargs="*", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for test in CASES:
        if args.cases and test["id"] not in args.cases:
            continue
        record = run_case(test, args.model)
        record["scores"] = grade(test, record)
        record = annotate_record(test, record)
        (args.output / f"{test['id']}.json").write_text(json.dumps(record, ensure_ascii=False, indent=2))
        print(test["id"], record["scores"], flush=True)


if __name__ == "__main__":
    main()
