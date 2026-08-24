import XCTest
@testable import HorongAI

/// 월간 목표 파서의 특성화 테스트.
///
/// 이 파서는 앱에서 `private func parseMonthly` 였어서 **어떤 테스트도 닿을 수 없었다.**
/// 패키지로 나오면서 처음 검증 가능해졌다 — 주간 파서(`GoalSuggestionParserTests`, 앱)와 달리
/// 방어 로직이 전혀 못 박혀 있지 않았다.
final class MonthlyGoalParseTests: XCTestCase {

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n)) ?? UUID()
    }

    /// `n` 번 주간 목표에는 `n00` 번대 할일이 하나 달려 있다 — 할일이 딸려 올라오는지 보려는 장치다.
    private func goal(_ n: Int) -> MonthlyGoalTask.Goal {
        MonthlyGoalTask.Goal(
            id: uuid(n),
            title: "주간 목표 \(n)",
            emoji: "🎯",
            rule: "연결한 할일 2개 완료",
            done: 1,
            total: 2,
            sourceMemoIDs: [uuid(n * 100)],
            roleName: "기획자",
            vision: "반복 업무를 줄인다"
        )
    }

    private var sourceGoals: [MonthlyGoalTask.Goal] { (1...5).map(goal) }

    private func json(_ items: String) -> String {
        "{\"suggestions\": [\(items)]}"
    }

    private func item(
        title: String = "분기 리포트 체계 완성",
        goalIDs: [Int],
        scheduleText: String = "이번 달에 주간 목표 2개로 나눠 진행",
        criterion: String = "연결한 주간 목표 2개 달성",
        emoji: String? = "📈"
    ) -> String {
        let ids = goalIDs.map { "\"\(uuid($0).uuidString)\"" }.joined(separator: ", ")
        let emojiField = emoji.map { "\"emoji\": \"\($0)\"" } ?? "\"emoji\": null"
        return """
        {"title": "\(title)", "reason": "같은 결과물로 이어진다", "goalIDs": [\(ids)],
         "scheduleText": "\(scheduleText)", "criterion": "\(criterion)", \(emojiField)}
        """
    }

    /// 이 파일은 **어떤 초안이 남는가**만 본다. 왜 그만큼만 남았는지(진단)는
    /// `MonthlyGoalDiagnosticsTests` 가 맡는다.
    private func parse(
        _ text: String,
        suggestionCount: Int = 3,
        maxGoalsPerSuggestion: Int = MonthlyGoalTask.maxGoalsPerSuggestion
    ) -> [GoalSuggestionDraft] {
        MonthlyGoalTask.parse(
            text,
            allowedIDs: Set(sourceGoals.map(\.id)),
            sourceGoals: sourceGoals,
            suggestionCount: suggestionCount,
            maxGoalsPerSuggestion: maxGoalsPerSuggestion
        ).drafts
    }

    // MARK: - 정상 경로

    /// 묶인 주간 목표의 할일까지 월간 후보로 끌어올린다. 이게 빠지면 월간 목표에 할일이 하나도 안 붙는다.
    func testRollsUpMemoIDsOfChildGoals() {
        let drafts = parse(json(item(goalIDs: [1, 2])))

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.childGoalIDs, [uuid(1), uuid(2)])
        XCTAssertEqual(Set(drafts.first?.memoIDs ?? []), [uuid(100), uuid(200)])
        XCTAssertEqual(drafts.first?.targetValueText, "2개")
    }

    // MARK: - 방어 경로

    func testBrokenJSONReturnsEmpty() {
        XCTAssertTrue(parse("이건 JSON 이 아니다").isEmpty)
    }

    /// 주간 목표가 2개 미만이면 월간으로 묶을 것이 없다.
    func testDropsSuggestionWithFewerThanTwoGoals() {
        XCTAssertTrue(parse(json(item(goalIDs: [1]))).isEmpty)
        XCTAssertTrue(parse(json(item(goalIDs: [1, 999]))).isEmpty, "허용 목록에 없는 id 는 세지 않는다")
    }

    /// 한 월간 목표에 주간 목표는 4개까지다. 초과분은 버린다.
    func testTrimsToFourChildGoals() {
        XCTAssertEqual(parse(json(item(goalIDs: [1, 2, 3, 4, 5]))).first?.childGoalIDs.count, 4)
    }

    func testRespectsConfiguredMaximumChildGoals() {
        XCTAssertEqual(
            parse(json(item(goalIDs: [1, 2, 3, 4, 5])), maxGoalsPerSuggestion: 2).first?.childGoalIDs.count,
            2
        )
    }

    /// 같은 주간 목표를 두 후보에 넣으면 뒤쪽에서 제거되고, 2개 미만이 되면 그 후보가 버려진다.
    func testDoesNotReuseSameGoalAcrossSuggestions() {
        let text = json([
            item(title: "첫째", goalIDs: [1, 2]),
            item(title: "둘째", goalIDs: [1, 2, 3])
        ].joined(separator: ", "))

        let drafts = parse(text)
        XCTAssertEqual(drafts.map(\.title), ["첫째"], "남은 id 가 1개뿐이라 둘째는 버려진다")
    }

    func testTrimsToSuggestionCount() {
        let text = json([
            item(title: "하나", goalIDs: [1, 2]),
            item(title: "둘", goalIDs: [3, 4])
        ].joined(separator: ", "))

        XCTAssertEqual(parse(text, suggestionCount: 1).count, 1)
    }

    // MARK: - 빈 값 채우기

    func testFillsEmptyFieldsWithDefaults() {
        let text = json(item(title: "", goalIDs: [1, 2], scheduleText: "", criterion: "", emoji: nil))
        let draft = parse(text).first

        XCTAssertEqual(draft?.title, "추천 월간 목표")
        XCTAssertEqual(draft?.scheduleText, "이번 달에 주간 목표 2개로 나눠 진행")
        XCTAssertEqual(draft?.criterion, "연결한 주간 목표 2개 달성")
        XCTAssertEqual(draft?.emoji, "📅")
    }
}
