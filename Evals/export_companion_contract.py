"""평가기(`companion_eval.py`)의 판단 계약을 픽스처로 내보낸다.

앱(`CompanionIntentTask`)은 이 픽스처와 같은 지시문·양식을 보내야 평가 결과를 그대로 믿을 수 있다.
Swift 테스트(`CompanionIntentContractTests`)가 앱 쪽을, `test_companion_contract.py` 가 평가기 쪽을 비교한다.
평가기 규칙을 바꾼 뒤에만 다시 실행한다: `python3 Evals/export_companion_contract.py`
"""
import json
from pathlib import Path

from companion_eval import ANSWER_SYSTEM, CASES, SCHEMA, SYSTEM

FIXTURES = Path(__file__).parent / "fixtures" / "prompts"
FILES = {
    "companion_intent_decision.txt": SYSTEM,
    "companion_intent_answer_rules.txt": ANSWER_SYSTEM,
    "companion_intent_schema.json": json.dumps(SCHEMA, ensure_ascii=False, indent=2) + "\n",
    # 앱이 코드로 먼저 가로채는 저장 지시 규칙이 평가 사례를 빼앗지 않는지 앱 테스트가 확인한다.
    "companion_intent_cases.json": json.dumps([{"id": c["id"], "message": c["message"], "expected_action": c["expected_action"]}
                                                for c in CASES], ensure_ascii=False, indent=2) + "\n",
}


def main():
    for name, text in FILES.items():
        (FIXTURES / name).write_text(text, encoding="utf-8")
        print("wrote", FIXTURES / name)


if __name__ == "__main__":
    main()
