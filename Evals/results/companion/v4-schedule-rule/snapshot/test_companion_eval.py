import copy
import unittest
from companion_eval import CASES, FakeTools, SEED, grade, run_case, annotate_record


def decision(action="conversation", **kwargs):
    return dict(action=action, date="", after="", title="", next_only=False, **{}) | kwargs


class EvaluationTests(unittest.TestCase):
    def test_answer_context_distinguishes_no_tool_from_empty_results(self):
        import json
        for key, d, status in [
            ("recall", decision("history_recall"), "not_requested"),
            ("empty", decision("schedule_lookup", date="2026-09-20"), "success_empty"),
            ("goal", decision("goal_lookup"), "success"),
        ]:
            test = next(x for x in CASES if x["id"] == key)
            def chat(model, messages, schema=None):
                return {"message": {"content": json.dumps(d) if schema else "답변"}}
            record = run_case(test, "fixture", chat)
            self.assertEqual(record["answer_context"]["tool_status"], status)
            self.assertEqual(record["answer_input"][-1], {"role": "user", "content": test["message"]})
            if key == "recall":
                self.assertEqual(record["answer_context"]["source"], "conversation_history")
                self.assertEqual(record["answer_input"][1:-1], test["history"])
                self.assertNotIn("result", record["answer_context"])

    def test_answer_context_removes_internal_ids_without_mutating_evidence(self):
        import json
        test = next(x for x in CASES if x["id"] == "tomorrow")
        def chat(model, messages, schema=None):
            return {"message": {"content": json.dumps(decision("schedule_lookup", date="2026-09-19")) if schema else "답변"}}
        record = run_case(test, "fixture", chat)
        self.assertEqual(record["events"][0]["result"][0]["id"], "t3")
        self.assertNotIn("id", record["answer_context"]["result"][0])
        self.assertEqual(record["answer_context"]["current_weekday"], "금요일")

    def test_cli_records_manifest_and_rejects_overwrite(self):
        import json
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        from companion_eval import main
        def fake_run(test, model):
            return dict(id=test["id"], decision=decision(), final_state=copy.deepcopy(SEED),
                        events=[], answer="준비를 도와드릴게요.")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "run-01"
            argv = ["eval", "--cases", "worry", "--output", str(output)]
            with patch("sys.argv", argv), patch("companion_eval.run_case", side_effect=fake_run) as run:
                main()
                manifest = json.loads((output / "manifest.json").read_text())
                self.assertEqual(manifest["completed_cases"], ["worry"])
                self.assertEqual(manifest["prompt_version"], "v4")
                with self.assertRaises(SystemExit):
                    main()
                self.assertEqual(run.call_count, 1)

    def test_tomorrow_must_return_all_items(self):
        test = next(x for x in CASES if x["id"] == "tomorrow")
        tools = FakeTools()
        d = decision("schedule_lookup", date="2026-09-19", next_only=True)
        tools.execute(d, test["id"])
        scores = grade(test, dict(decision=d, final_state=tools.items, events=tools.events))
        self.assertFalse(scores["intent"])
        self.assertFalse(scores["execution"])

    def test_unused_arguments_and_invented_time_fail_intent(self):
        for key, d in [
            ("help", decision("app_help", date="2026-09-18")),
            ("create", decision("schedule_create", date="2026-09-18", title="호롱호롱 앱 배포하기", after="00:00")),
            ("today", decision("schedule_lookup", date="2026-09-18", after="10:00")),
        ]:
            test = next(x for x in CASES if x["id"] == key)
            tools = FakeTools()
            tools.execute(d, key)
            self.assertFalse(grade(test, dict(decision=d, final_state=tools.items, events=tools.events))["intent"])

    def test_saved_goal_differs_from_history(self):
        result = FakeTools().execute(decision("goal_lookup"), "goal")
        self.assertNotIn("이번 달 포트폴리오 완성", result["goals"])

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
        for date, after, ids in [("2026-09-18", "", ["t1", "t2"]), ("2026-09-19", "", ["t3", "t5"]), ("2026-09-18", "14:00", ["t2"])]:
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
