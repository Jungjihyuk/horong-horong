import json
import unittest

from companion_eval import CASES, SEED
from companion_eval_native import annotate, grade_native, run_case

CASE = {test["id"]: test for test in CASES}


def reply(content="", *calls):
    message = {"role": "assistant", "content": content}
    if calls:
        message["tool_calls"] = [{"function": {"name": name, "arguments": args}} for name, args in calls]
    return {"message": message}


def scripted(*responses):
    """모델 응답을 순서대로 돌려주는 가짜 chat. 받은 메시지는 calls 에 남긴다."""
    queue = list(responses)
    calls = []

    def chat(model, messages, tools=None):
        calls.append(messages)
        response = queue.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    chat.calls = calls
    return chat


def run(case_id, *responses):
    chat = scripted(*responses)
    record = run_case(CASE[case_id], "fake", chat=chat)
    record["scores"] = grade_native(CASE[case_id], record)
    return record, chat


class NativeEvaluationTests(unittest.TestCase):
    def test_direct_answer_passes_no_tool_case_with_single_call(self):
        record, chat = run("worry", reply("준비가 걱정되시는군요."))
        self.assertEqual(record["scores"]["intent"], True)
        self.assertEqual(record["scores"]["execution"], True)
        self.assertEqual(len(chat.calls), 1)
        self.assertEqual(record["answer"], "준비가 걱정되시는군요.")

    def test_tool_call_on_negation_fails_and_is_observed(self):
        record, _ = run("negation", reply("", ("schedule_create", {"title": "걱정", "date": "2026-09-19"})),
                        reply("저장했어요."))
        self.assertFalse(record["scores"]["intent"])
        self.assertFalse(record["scores"]["execution"])
        self.assertNotEqual(record["final_state"], SEED)

    def test_lookup_returns_context_without_ids_as_tool_message(self):
        record, chat = run("tomorrow", reply("", ("schedule_lookup", {"date": "2026-09-19"})), reply("내일 일정은 두 개예요."))
        self.assertTrue(record["scores"]["intent"])
        self.assertTrue(record["scores"]["execution"])
        tool_message = chat.calls[1][-1]
        self.assertEqual(tool_message["role"], "tool")
        context = json.loads(tool_message["content"])
        self.assertEqual(context["tool_status"], "success")
        self.assertTrue(all("id" not in item for item in context["result"]))

    def test_missing_tool_call_is_decision_error_not_format_error(self):
        record, _ = run("tomorrow", reply("내일 일정을 조회해 드릴까요?"))
        self.assertFalse(record["scores"]["intent"])
        self.assertFalse(record["scores"]["execution"])
        self.assertEqual(record["scores"]["error"], "missing_tool_call")

    def test_two_tool_calls_fail_intent(self):
        record, _ = run("today", reply("", ("schedule_lookup", {"date": "2026-09-18"}),
                                       ("schedule_lookup", {"date": "2026-09-18"})), reply("오늘 일정이에요."))
        self.assertFalse(record["scores"]["intent"])

    def test_invented_time_on_create_fails_intent(self):
        record, _ = run("create", reply("", ("schedule_create", {"title": "호롱호롱 앱 배포하기", "date": "2026-09-18",
                                                                 "after": "00:00"})), reply("추가했어요."))
        self.assertFalse(record["scores"]["intent"])

    def test_create_with_requested_values_passes(self):
        record, _ = run("create", reply("", ("schedule_create", {"title": "호롱호롱 앱 배포하기", "date": "2026-09-18"})),
                        reply("추가했어요."))
        self.assertTrue(record["scores"]["intent"])
        self.assertTrue(record["scores"]["execution"])

    def test_extra_tool_call_in_answer_step_is_recorded_not_executed(self):
        record, _ = run("goal", reply("", ("goal_lookup", {})),
                        reply("", ("schedule_create", {"title": "러닝", "date": "2026-09-18"})))
        self.assertEqual(len(record["events"]), 1)
        self.assertEqual(record["extra_tool_calls"][0]["name"], "schedule_create")
        self.assertEqual(record["final_state"], SEED)

    def test_server_rejection_is_infrastructure_not_model_failure(self):
        record, _ = run("today", OSError("HTTP 400: does not support tools"))
        self.assertIsNone(record["scores"]["intent"])
        self.assertIn("does not support tools", record["infrastructure_error"])

    def test_review_status_follows_native_scores(self):
        record, _ = run("recall", reply("포트폴리오 완성이라고 하셨어요."))
        reviewed = annotate(CASE["recall"], record)
        self.assertEqual(reviewed["review"]["intent"]["status"], "pass")
        self.assertEqual(reviewed["review"]["execution"]["status"], "pass")


if __name__ == "__main__":
    unittest.main()
