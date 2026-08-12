import XCTest
@testable import 호롱호롱

/// 목표 추천 **파서**의 현재 동작을 못 박는 특성화 테스트.
///
/// S4 에서 이 파서를 `AchievementViews.swift`(8,949줄)에서 `Tasks/GoalRecommendation/` 으로 꺼낸다.
/// 파서는 모델이 뱉은 JSON 을 믿지 않고 다섯 갈래로 방어하는데, 옮기다 한 갈래를 빠뜨려도
/// **실모델 점수로는 알아챌 수 없다** — 모델이 매번 다르게 답하기 때문이다.
/// (참고: `docs/.../Bug/incident-20260813-nondeterministic-model-breaks-regression-check.md`)
///
/// 그래서 모델 없이 고정된 JSON 을 넣어 결과를 비교한다.
@available(macOS 26.0, *)
final class GoalSuggestionParserTests: XCTestCase {

    private let parser = FoundationModelsGoalSuggestionProvider()

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n))!
    }

    private func json(_ items: String) -> String {
        "{\"suggestions\": [\(items)]}"
    }

    private func item(
        title: String = "주간 보고서 마무리",
        reason: String = "같은 결과물로 이어진다",
        memoIDs: [Int],
        scheduleText: String = "월/수에 나눠 진행",
        criterion: String = "연결한 할일 2개 완료",
        emoji: String? = "📝"
    ) -> String {
        let ids = memoIDs.map { "\"\(uuid($0).uuidString)\"" }.joined(separator: ", ")
        let emojiField = emoji.map { "\"emoji\": \"\($0)\"" } ?? "\"emoji\": null"
        return """
        {"title": "\(title)", "reason": "\(reason)", "memoIDs": [\(ids)],
         "scheduleText": "\(scheduleText)", "criterion": "\(criterion)", \(emojiField)}
        """
    }

    private func parse(
        _ text: String,
        allowed: [Int] = [1, 2, 3, 4, 5],
        suggestionCount: Int = 3,
        maxMemoCount: Int = 3
    ) -> [AchievementGoalSuggestion] {
        parser.parse(
            text,
            allowedIDs: Set(allowed.map(uuid)),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        )
    }

    // MARK: - 정상 경로

    func testParsesValidSuggestion() {
        let result = parse(json(item(memoIDs: [1, 2])))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "주간 보고서 마무리")
        XCTAssertEqual(result.first?.memoIDs.count, 2)
        XCTAssertEqual(result.first?.targetValueText, "2개")
    }

    /// 모델이 JSON 앞뒤에 설명을 붙여도 살려낸다 — 첫 `{` 부터 마지막 `}` 까지만 자른다.
    func testExtractsJSONFromSurroundingText() {
        let text = "알겠습니다! 아래가 제안입니다.\n\(json(item(memoIDs: [1, 2])))\n도움이 되었길 바랍니다."
        XCTAssertEqual(parse(text).count, 1)
    }

    // MARK: - 방어 경로 다섯 갈래

    /// ① JSON 이 깨지면 빈 배열. 예외를 던지지 않는다.
    func testBrokenJSONReturnsEmpty() {
        XCTAssertTrue(parse("이건 JSON 이 아니다").isEmpty)
        XCTAssertTrue(parse("{\"suggestions\": [").isEmpty)
    }

    /// ② 허용 목록에 없는 id 는 버린다. 모델이 id 를 지어내는 일이 있다.
    func testDropsUnknownIDs() {
        let text = json(item(memoIDs: [1, 2, 99]))
        XCTAssertEqual(parse(text, allowed: [1, 2]).first?.memoIDs.count, 2)
    }

    /// id 를 걸러낸 결과가 2개 미만이면 **제안 자체를 버린다.**
    func testDropsSuggestionWhenTooFewValidIDs() {
        let text = json(item(memoIDs: [1, 99]))
        XCTAssertTrue(parse(text, allowed: [1]).isEmpty)
    }

    /// ③ 같은 할일을 두 제안에 넣으면 뒤쪽에서 제거된다. 결과가 2개 미만이면 그 제안이 버려진다.
    func testDoesNotReuseSameMemoAcrossSuggestions() {
        let text = json([
            item(title: "첫째", memoIDs: [1, 2]),
            item(title: "둘째", memoIDs: [1, 2])
        ].joined(separator: ", "))

        let result = parse(text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "첫째")
    }

    /// ④ 한 제안에 `maxMemoCount` 를 넘게 넣으면 초과분을 버린다.
    func testTrimsToMaxMemoCount() {
        let text = json(item(memoIDs: [1, 2, 3, 4]))
        XCTAssertEqual(parse(text, maxMemoCount: 3).first?.memoIDs.count, 3)
    }

    /// ⑤ 제안 개수도 상한을 넘으면 잘린다.
    func testTrimsToSuggestionCount() {
        let text = json([
            item(title: "하나", memoIDs: [1, 2]),
            item(title: "둘", memoIDs: [3, 4]),
            item(title: "셋", memoIDs: [5, 1])
        ].joined(separator: ", "))

        XCTAssertEqual(parse(text, suggestionCount: 2).count, 2)
    }

    // MARK: - 빈 값 채우기

    /// 모델이 빈 문자열을 주면 사람이 읽을 수 있는 기본값으로 메운다.
    func testFillsEmptyFieldsWithDefaults() {
        let text = json(item(title: "", memoIDs: [1, 2], scheduleText: "", criterion: "", emoji: nil))
        let suggestion = parse(text).first

        XCTAssertEqual(suggestion?.title, "추천 목표")
        XCTAssertEqual(suggestion?.scheduleText, "이번 주에 나눠 진행")
        XCTAssertEqual(suggestion?.criterion, "연결한 할일 2개 완료")
        XCTAssertEqual(suggestion?.emoji, "🎯")
    }

    /// 이모지를 여러 글자 보내면 **첫 글자만** 쓴다. 목록에 두 칸을 차지하면 정렬이 깨진다.
    func testKeepsOnlyFirstEmojiCharacter() {
        let text = json(item(memoIDs: [1, 2], emoji: "📝✅🎯"))
        XCTAssertEqual(parse(text).first?.emoji, "📝")
    }

    /// 출처가 모델임을 표시한다 — 룰 기반 폴백과 구분해야 "AI 가 실제로 답했는가"를 알 수 있다.
    func testMarksSourceAsFoundationModel() {
        XCTAssertEqual(parse(json(item(memoIDs: [1, 2]))).first?.source, .foundationModel)
    }
}
