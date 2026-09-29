import HorongAI
import XCTest
@testable import 호롱호롱

/// 앱이 평가기(`Evals/companion_eval.py` v5)와 **같은 계약**으로 모델을 부르는지 본다.
///
/// 픽스처는 평가기가 만든다(`python3 Evals/export_companion_contract.py`). 이 테스트에는 기록 모드가 없다 —
/// 앱 쪽을 바꿔 맞추면 평가하지 않은 계약으로 앱이 돌게 되므로, 바꾸려면 평가기부터 고치고 다시 잰다.
final class CompanionIntentContractTests: XCTestCase {
    private let evaluatorNow = ISO8601DateFormatter().date(from: "2026-09-18T01:00:00Z")!
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    func testDecisionInstructionsMatchEvaluator() throws {
        XCTAssertEqual(
            CompanionIntentTask.decisionInstructions(now: evaluatorNow, timeZone: seoul),
            try fixture("companion_intent_decision.txt")
        )
    }

    func testAnswerRulesMatchEvaluator() throws {
        XCTAssertEqual(CompanionIntentTask.answerRules, try fixture("companion_intent_answer_rules.txt"))
    }

    /// 뜻이 같고, 속성 순서도 같아야 한다(순서가 곧 생성 문법이다 → `JSONSchema`).
    func testDecisionSchemaMatchesEvaluator() throws {
        let appText = CompanionIntentTask.decisionSchema.jsonText
        let evaluatorText = try fixture("companion_intent_schema.json")
        let app = try JSONSerialization.jsonObject(with: Data(appText.utf8)) as? NSDictionary
        let evaluator = try JSONSerialization.jsonObject(with: Data(evaluatorText.utf8)) as? NSDictionary
        XCTAssertEqual(app, evaluator)

        let order = ["\"action\"", "\"date\"", "\"after\"", "\"title\"", "\"next_only\""]
        for text in [appText, evaluatorText] {
            let positions = order.compactMap { text.range(of: $0)?.lowerBound }
            XCTAssertEqual(positions, positions.sorted(), text)
        }
    }

    /// 앱에 남긴 저장 지시 규칙은 모델보다 먼저 돈다. 평가 사례를 가로채면 평가한 판단이 앱에서 쓰이지 않는다.
    func testSaveCommandRuleDoesNotTakeEvaluationCases() throws {
        let cases = try JSONDecoder().decode(
            [EvaluationCase].self,
            from: Data(try fixture("companion_intent_cases.json").utf8)
        )
        XCTAssertEqual(cases.count, 21)
        for item in cases {
            XCTAssertNil(CompanionMemoIntent.parse(item.message), "\(item.id): \(item.message)")
        }
    }

    /// 판단 입력은 지시문 → 최근 말풍선 → 이번 말 순서다. 빈 말풍선(일정 카드만 있는 답)은 뺀다.
    func testDecisionMessagesKeepRecentHistoryInOrder() {
        var history = (1...8).map { CompanionChatMessage(role: $0.isMultiple(of: 2) ? .companion : .user, text: "말\($0)") }
        history.append(CompanionChatMessage(role: .companion, text: ""))
        let messages = CompanionIntentDecider.messages(history: history, message: "지금", now: evaluatorNow, timeZone: seoul)

        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertEqual(messages.last?.content, "지금")
        XCTAssertEqual(messages.dropFirst().dropLast().map(\.content), ["말3", "말4", "말5", "말6", "말7", "말8"])
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[2].role, "assistant")
    }

    /// 연결 확인 캐시에 막히지 않는다. Ollama 를 골랐으면 판단을 시도하고, 실패하면 기존 흐름으로 돌아간다.
    func testDecisionIsAttemptedWheneverOllamaIsSelected() {
        let decider = CompanionIntentDecider.make(selectedOllama: ("http://127.0.0.1:11434", "gemma4:e4b"))
        XCTAssertEqual(decider?.endpoint, "http://127.0.0.1:11434")
        XCTAssertEqual(decider?.model, "gemma4:e4b")
        XCTAssertNil(CompanionIntentDecider.make(selectedOllama: nil))
    }

    private struct EvaluationCase: Decodable {
        let id: String
        let message: String
    }

    private func fixture(_ name: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let evals = url.appendingPathComponent("Evals")
            if FileManager.default.fileExists(atPath: evals.path) {
                return try String(
                    contentsOf: evals.appendingPathComponent("fixtures/prompts/\(name)"),
                    encoding: .utf8
                )
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
