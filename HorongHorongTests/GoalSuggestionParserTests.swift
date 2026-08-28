import HorongAI
import XCTest
@testable import 호롱호롱

/// 파서가 낸 결과에 **앱이 덧붙이는 것**을 지킨다.
///
/// 파싱 자체(JSON 방어 다섯 갈래·빈 값 채우기·예산 컷)는 패키지로 옮겨
/// `HorongAITests/WeeklyGoalTaskTests` 가 앱 빌드 없이 0.04초에 돈다.
/// 여기 남은 둘은 패키지가 알 수 없는 값이다.
///
/// - `source`: 실제로 **누가 답했는가**. 태스크는 `generate` 클로저만 받아 공급자를 모르고,
///   폴백(MLX → AFM → 룰)까지 있어 돌려봐야 안다.
/// - `reason` 72자: 추천 카드가 2줄까지만 보여준다. **얼마나 줄일지는 화면이 정한다.**
final class GoalSuggestionParserTests: XCTestCase {

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n)) ?? UUID()
    }

    private func json(reason: String = "같은 결과물로 이어진다", memoIDs: [Int]) -> String {
        let ids = memoIDs.map { "\"\(uuid($0).uuidString)\"" }.joined(separator: ", ")
        return """
        {"suggestions": [{"title": "주간 보고서 마무리", "reason": "\(reason)", "memoIDs": [\(ids)],
         "scheduleText": "월/수에 나눠 진행", "criterion": "연결한 할일 2개 완료", "emoji": "📝"}]}
        """
    }

    /// 패키지가 파싱한 초안을 앱 값으로 바꾸는 경로 — 이 변환이 이 파일의 검증 대상이다.
    private func parse(_ text: String) -> [AchievementGoalSuggestion] {
        WeeklyGoalTask.parse(
            text,
            allowedIDs: Set([1, 2, 3, 4, 5].map(uuid)),
            suggestionCount: 3,
            maxMemoCount: 3
        ).drafts.map { $0.suggestion(cadence: .weekly) }
    }

    /// 출처가 모델임을 표시한다 — 룰 기반 폴백과 구분해야 "AI 가 실제로 답했는가"를 알 수 있다.
    func testMarksSourceAsFoundationModel() {
        XCTAssertEqual(parse(json(memoIDs: [1, 2])).first?.source, .foundationModel)
    }

    /// 모델이 이유를 길게 쓰면 카드에 들어갈 만큼만 남긴다. 패키지는 원본을 그대로 넘긴다.
    func testReasonIsClippedForTheCard() {
        let long = String(repeating: "가", count: 200)
        let reason = try? XCTUnwrap(parse(json(reason: long, memoIDs: [1, 2])).first?.reason)

        XCTAssertEqual(reason?.count, 75, "72자 + 말줄임표")
        XCTAssertTrue(reason?.hasSuffix("...") == true)
    }

    /// 여러 줄로 오면 첫 줄만 쓴다. 안 그러면 카드 레이아웃이 밀린다.
    func testMultilineReasonKeepsOnlyTheFirstLine() {
        let reason = parse(json(reason: "첫 줄이다\\n둘째 줄이다", memoIDs: [1, 2])).first?.reason

        XCTAssertEqual(reason, "첫 줄이다")
    }
}
