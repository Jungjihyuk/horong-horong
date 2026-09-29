import unittest

from export_companion_contract import FILES, FIXTURES


class CompanionContractFixtureTests(unittest.TestCase):
    """평가기 규칙이 바뀌었는데 픽스처를 다시 내보내지 않으면, 앱이 옛 계약으로 돌게 된다."""

    def test_fixtures_match_evaluator(self):
        for name, text in FILES.items():
            with self.subTest(name=name):
                self.assertEqual((FIXTURES / name).read_text(encoding="utf-8"), text,
                                 "python3 Evals/export_companion_contract.py 로 다시 내보낸다")


if __name__ == "__main__":
    unittest.main()
