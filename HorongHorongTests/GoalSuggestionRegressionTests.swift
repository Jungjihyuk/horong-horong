import XCTest
@testable import 호롱호롱

/// 2026-07-31 인시던트(AFM 추론 100% 실패)와 그 후속 수정을 지키는 회귀 테스트.
///
/// 모델 호출 없이 도는 순수 로직만 다룬다. 추론이 필요한 품질 평가는
/// `GoalSuggestionEvalTests`(골든셋)가 담당한다.
@available(macOS 26.0, *)
final class GoalSuggestionRegressionTests: XCTestCase {

    private let provider = FoundationModelsGoalSuggestionProvider()

    private func memo(
        _ content: String,
        id: UUID = UUID(),
        startDate: Date? = nil,
        deadline: Date? = nil,
        isCompleted: Bool = false
    ) -> AchievementMemoSnapshot {
        AchievementMemoSnapshot(
            id: id,
            content: content,
            icon: "📝",
            date: Date(timeIntervalSince1970: 1_785_000_000),
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompleted
        )
    }

    // MARK: - 프롬프트 예산
    // 인시던트 원인: 프롬프트가 커지면 추론이 통째로 거부된다(에러명은 unsupportedLanguageOrLocale로 오분류).

    func testPromptStaysWithinBudgetEvenWithManyLongMemos() {
        let memos = (0..<40).map { i in
            memo(String(repeating: "긴 메모 본문 예시 ", count: 12) + "\(i)")
        }
        let selected = provider.memosWithinPromptBudget(memos, suggestionCount: 4, maxMemoCount: 5)
        let text = provider.prompt(for: selected, suggestionCount: 4, maxMemoCount: 5)

        XCTAssertLessThanOrEqual(
            text.count, achievementPromptCharacterBudget,
            "프롬프트가 예산을 넘으면 추론이 거부된다"
        )
        XCTAssertLessThan(selected.count, memos.count, "예산을 맞추려면 일부는 잘려야 한다")
    }

    func testBudgetCutKeepsAtLeastTwoMemos() {
        // 묶으려면 최소 2개가 필요하다. 예산을 넘더라도 1개까지 줄이면 추천 자체가 불가능해진다.
        let huge = String(repeating: "아주 긴 본문 ", count: 400)
        let memos = [memo(huge), memo(huge), memo(huge)]
        let selected = provider.memosWithinPromptBudget(memos, suggestionCount: 4, maxMemoCount: 5)
        XCTAssertGreaterThanOrEqual(selected.count, 2)
    }

    func testShortInputIsNotTrimmed() {
        let memos = (0..<3).map { memo("짧은 할일 \($0)") }
        let selected = provider.memosWithinPromptBudget(memos, suggestionCount: 4, maxMemoCount: 5)
        XCTAssertEqual(selected.count, 3, "예산에 여유가 있으면 자르지 않는다")
    }

    // MARK: - 직렬화 다이어트
    // 값이 없는 필드를 "없음"으로 채우면 메모당 30자 이상을 정보 없이 소비한다.

    func testEmptyDateFieldsAreOmitted() {
        let text = provider.prompt(for: [memo("아침 러닝")], suggestionCount: 4, maxMemoCount: 5)
        XCTAssertFalse(text.contains("startDate:"), "startDate가 없으면 줄 자체를 넣지 않는다")
        XCTAssertFalse(text.contains("deadline:"), "deadline이 없으면 줄 자체를 넣지 않는다")
        XCTAssertFalse(text.contains("없음"), "빈 값을 문자열로 채우지 않는다")
    }

    func testPresentDateFieldsAreIncluded() {
        let due = Date(timeIntervalSince1970: 1_785_600_000)
        let text = provider.prompt(
            for: [memo("보고서 제출", deadline: due)],
            suggestionCount: 4,
            maxMemoCount: 5
        )
        XCTAssertTrue(text.contains("deadline:"), "값이 있으면 반드시 전달한다")
    }

    func testCompletedFlagOmittedWhenFalse() {
        // 미완료 할일만 입력으로 들어오므로 항상 false인 줄을 40번 반복할 이유가 없다.
        let text = provider.prompt(for: [memo("아침 러닝")], suggestionCount: 4, maxMemoCount: 5)
        XCTAssertFalse(text.contains("completed:"))
    }

    // MARK: - 응답 파싱
    // parsed=1 진단 과정에서 파서가 후보를 버리는 경로가 넷임을 확인했다.

    private func payload(_ groups: [[UUID]]) -> String {
        let items = groups.map { ids in
            let list = ids.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
            return """
            {"title":"목표","reason":"이유","memoIDs":[\(list)],"scheduleText":"","criterion":"","emoji":"🎯"}
            """
        }.joined(separator: ",")
        return "{\"suggestions\":[\(items)]}"
    }

    func testParseDropsUnknownIDs() {
        let known = [UUID(), UUID()]
        let text = payload([[known[0], known[1], UUID()]])   // 마지막은 입력에 없던 id
        let parsed = provider.parse(text, allowedIDs: Set(known), suggestionCount: 4, maxMemoCount: 5)
        XCTAssertEqual(parsed.first?.memoIDs.count, 2, "존재하지 않는 id는 버린다")
    }

    func testParseRejectsSuggestionWithFewerThanTwoIDs() {
        let known = [UUID()]
        let parsed = provider.parse(payload([known]), allowedIDs: Set(known), suggestionCount: 4, maxMemoCount: 5)
        XCTAssertTrue(parsed.isEmpty, "메모 1개짜리는 묶음이 아니다")
    }

    func testParseDoesNotReuseMemoAcrossSuggestions() {
        let ids = [UUID(), UUID(), UUID()]
        // 두 후보가 같은 메모를 요청하면 뒤엣것은 남은 개수가 모자라 폐기된다.
        let text = payload([[ids[0], ids[1]], [ids[0], ids[1], ids[2]]])
        let parsed = provider.parse(text, allowedIDs: Set(ids), suggestionCount: 4, maxMemoCount: 5)
        let used = parsed.flatMap(\.memoIDs)
        XCTAssertEqual(Set(used).count, used.count, "같은 메모가 여러 후보에 중복될 수 없다")
    }

    func testParseTrimsToMaxMemoCount() {
        let ids = (0..<8).map { _ in UUID() }
        let parsed = provider.parse(payload([ids]), allowedIDs: Set(ids), suggestionCount: 4, maxMemoCount: 3)
        XCTAssertEqual(parsed.first?.memoIDs.count, 3, "한 목표에 maxMemoCount를 넘겨 담지 않는다")
    }

    func testParseReturnsEmptyOnMalformedJSON() {
        let parsed = provider.parse("이건 JSON이 아니다", allowedIDs: [], suggestionCount: 4, maxMemoCount: 5)
        XCTAssertTrue(parsed.isEmpty)
    }

    func testParsedSuggestionsAreTaggedAsModelOutput() {
        // source 가 틀리면 폴백 비율 집계가 통째로 어긋난다.
        let ids = [UUID(), UUID()]
        let parsed = provider.parse(payload([ids]), allowedIDs: Set(ids), suggestionCount: 4, maxMemoCount: 5)
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
