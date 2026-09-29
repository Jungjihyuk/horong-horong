import copy
import unittest
from companion_eval import CASES, FakeTools, SEED, grade, run_case, annotate_record


def decision(action="conversation", **kwargs):
    return dict(action=action, date="", after="", title="", next_only=False, **{}) | kwargs


class EvaluationTests(unittest.TestCase):
    def test_review_description_for_every_case(self):
        for test in CASES:
            record = dict(decision=decision(), final_state=copy.deepcopy(SEED), events=[], answer="예시")
            original = copy.deepcopy(record)
            annotated = annotate_record(test, record, backfilled=True)
            self.assertEqual(record, original)
            self.assertEqual(annotated["case_description"]["user_utterance"], test["message"])
            self.assertTrue(annotated["case_description"]["situation"])
            self.assertTrue(annotated["case_description"]["forbidden_behavior"])
            self.assertEqual(annotated["review"]["answer"]["status"], "review_required")
            self.assertTrue(annotated["annotation"]["backfilled"])

    def test_backfill_does_not_invent_original_prompt(self):
        record = dict(decision=decision(), final_state=copy.deepcopy(SEED), events=[], answer="답변")
        annotated = annotate_record(CASES[0], record, backfilled=True)
        self.assertNotIn("decision_input", annotated)

    def test_today_tomorrow_and_after(self):
        for date, after, ids in [("2026-09-18", "", ["t1", "t2"]), ("2026-09-19", "", ["t3"]), ("2026-09-18", "14:00", ["t2"])]:
            self.assertEqual([x["id"] for x in FakeTools().execute(decision("schedule_lookup", date=date, after=after), "x")], ids)

    def test_next(self):
        self.assertEqual(FakeTools().execute(decision("schedule_lookup", next_only=True), "x")[0]["id"], "t2")

    def test_duplicate_create(self):
        tools = FakeTools()
        d = decision("schedule_create", date="2026-09-18", title="배포")
        self.assertEqual(tools.execute(d, "x"), tools.execute(d, "x"))
        self.assertEqual(len(tools.items), len(SEED) + 1)

    def test_invalid_does_not_mutate(self):
        for d in [decision("delete_all"), decision("schedule_create"), decision("schedule_lookup", date="2026-02-31"), decision("schedule_lookup", date="20260918"), decision("schedule_lookup", date="2026-09-18", after="1400")]:
            tools = FakeTools()
            with self.assertRaises(ValueError):
                tools.execute(d, "x")
            self.assertEqual(tools.items, SEED)

    def test_grader_rejects_unrequested_write(self):
        tools = FakeTools()
        d = decision("schedule_create", date="2026-09-18", title="이력서")
        tools.execute(d, "worry")
        scores = grade(CASES[0], dict(decision=d, final_state=tools.items, events=tools.events, answer="저장했어요"))
        self.assertFalse(scores["intent"])
        self.assertFalse(scores["execution"])

    def test_grader_accepts_conversation_without_word_matching(self):
        scores = grade(CASES[0], dict(decision=decision(), final_state=copy.deepcopy(SEED), events=[], answer="준비할 자료부터 살펴볼까요?"))
        self.assertTrue(scores["intent"])
        self.assertTrue(scores["execution"])
        self.assertEqual(scores["answer"], "review_required")

    def test_grader_rejects_wrong_lookup(self):
        tools = FakeTools()
        d = decision("schedule_lookup", date="2026-09-18")
        tools.execute(d, "tomorrow")
        self.assertFalse(grade(CASES[4], dict(decision=d, final_state=tools.items, events=tools.events))["execution"])

    def test_infrastructure_not_model_failure(self):
        scores = grade(CASES[0], {"infrastructure_error": "timeout"})
        self.assertIsNone(scores["intent"])

    def test_invalid_output_fails_grader(self):
        for value in [None, {}, decision("unknown"), decision(next_only="false")]:
            scores = grade(CASES[0], {"decision": value})
            self.assertFalse(scores["intent"])
            self.assertFalse(scores["execution"])

    def test_missing_answer_not_passed(self):
        scores = grade(CASES[0], dict(decision=decision(), final_state=copy.deepcopy(SEED), events=[]))
        self.assertEqual(scores["answer"], "missing")

    def test_create_changes_only_requested_item(self):
        test = next(x for x in CASES if x["id"] == "create")
        tools = FakeTools()
        d = decision("schedule_create", **test["expected_args"])
        tools.execute(d, test["id"])
        record = dict(decision=d, final_state=tools.items, events=tools.events, answer="저장했어요")
        self.assertTrue(grade(test, record)["execution"])
        record["final_state"][0]["title"] = "예상치 못한 수정"
        self.assertFalse(grade(test, record)["execution"])

    def test_expected_values_never_sent(self):
        import json
        calls = []
        def chat(model, messages, schema=None):
            calls.append(messages)
            return {"message": {"content": json.dumps(decision()) if schema else "준비를 도와드릴게요."}}
        record = run_case(CASES[0], "fixture", chat)
        self.assertNotIn("expected_action", json.dumps(calls))
        self.assertNotIn("forbidden_behavior", json.dumps(calls))
        self.assertEqual(record["decision_input"], calls[0])
        self.assertEqual(len(calls), 2)
        self.assertEqual(record["final_state"], SEED)


if __name__ == "__main__":
    unittest.main()
