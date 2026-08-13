import HorongAI
import XCTest
@testable import 호롱호롱

/// 2026-07-31 인시던트(AFM 추론 100% 실패)와 그 후속 수정을 지키는 회귀 테스트 중
/// **앱에만 있는 것**들.
///
/// 프롬프트 예산·직렬화 다이어트·파서 방어는 패키지로 옮겨
/// `HorongAITests/WeeklyGoalTaskTests` 가 앱 빌드 없이 돈다.
/// 여기 남은 둘은 패키지가 모르는 앱 코드다 — 공급자 도장과 룰 기반 폴백.
final class GoalSuggestionRegressionTests: XCTestCase {

    private func memo(_ content: String, id: UUID = UUID()) -> AchievementMemoSnapshot {
        AchievementMemoSnapshot(
            id: id,
            content: content,
            icon: "📝",
            date: Date(timeIntervalSince1970: 1_785_000_000),
            startDate: nil,
            deadline: nil,
            isCompleted: false
        )
    }

    private func payload(_ groups: [[UUID]]) -> String {
        let items = groups.map { ids in
            let list = ids.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
            return """
            {"title":"목표","reason":"이유","memoIDs":[\(list)],"scheduleText":"","criterion":"","emoji":"🎯"}
            """
        }.joined(separator: ",")
        return "{\"suggestions\":[\(items)]}"
    }

    /// source 가 틀리면 폴백 비율 집계가 통째로 어긋난다.
    func testParsedSuggestionsAreTaggedAsModelOutput() {
        let ids = [UUID(), UUID()]
        let parsed = WeeklyGoalTask.parse(
            payload([ids]), allowedIDs: Set(ids), suggestionCount: 4, maxMemoCount: 5
        ).drafts.map { $0.suggestion(cadence: .weekly) }
        XCTAssertEqual(parsed.first?.source, .foundationModel)
    }

    // MARK: - 룰 기반 폴백
    // 폴백이 결정론적이라는 사실이 "항상 비슷한 추천"의 원인이었다. 이 성질 자체는 유지되어야 한다.

    func testRuleBasedFallbackIsDeterministic() {
        let memos = [
            memo("아침 러닝 30분"), memo("저녁 러닝 20분"), memo("러닝화 사기"),
            memo("보고서 초안"), memo("보고서 검토"),
        ]
        let first = AchievementGoalSuggestionBuilder.ruleBasedSuggestions(
            from: memos, suggestionCount: 4, maxMemoCount: 5
        )
        let second = AchievementGoalSuggestionBuilder.ruleBasedSuggestions(
            from: memos, suggestionCount: 4, maxMemoCount: 5
        )
        XCTAssertEqual(first.map(\.title), second.map(\.title), "같은 입력은 항상 같은 폴백을 낸다")
        XCTAssertTrue(first.allSatisfy { $0.source == .rule })
    }
}
