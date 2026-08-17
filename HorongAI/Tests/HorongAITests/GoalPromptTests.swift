import XCTest
@testable import HorongAI

/// 프롬프트가 **`.md` 에서** 만들어지는지 확인한다.
///
/// `PromptRenderer` 는 파일을 못 읽으면 조용히 폴백 문자열을 쓴다. 리소스 배선이 끊겨도
/// 빌드는 통과하고 앱도 돌아가지만, 프롬프트가 통째로 짧아져 추천 품질이 무너진다.
/// 앱 쪽 `PromptSnapshotTests` 도 이 사고를 잡지만 앱 타깃을 빌드해야 한다 — 여기서는 0.5초에 잡는다.
///
/// 월간 프롬프트는 앱 쪽 스냅샷이 없어, 자리표시자 치환을 확인하는 곳이 여기뿐이다.
final class GoalPromptTests: XCTestCase {

    private let memos = [
        WeeklyGoalTask.Memo(
            id: UUID(),
            content: "주간 보고서 초안 작성",
            icon: "doc",
            date: Date(timeIntervalSince1970: 1_770_000_000)
        ),
        WeeklyGoalTask.Memo(
            id: UUID(),
            content: "주간 보고서 검토 요청",
            icon: "doc",
            date: Date(timeIntervalSince1970: 1_770_000_000)
        ),
    ]

    private let goals = [
        MonthlyGoalTask.Goal(
            id: UUID(),
            title: "주간 리포트 자동화",
            emoji: "🎯",
            rule: "연결한 할일 3개 완료",
            done: 1,
            total: 3,
            sourceMemoIDs: [UUID()],
            roleName: "기획자",
            vision: "반복 업무를 줄인다"
        ),
    ]

    /// 폴백에는 없고 `weekly_goal.md` 에만 있는 문구다. 이게 없으면 파일을 못 읽은 것이다.
    func testWeeklyPromptComesFromMarkdownNotFallback() {
        let rendered = WeeklyGoalTask.prompt(for: memos, suggestionCount: 3, maxMemoCount: 3)
        XCTAssertTrue(rendered.contains("[가장 중요한 묶는 기준]"), "weekly_goal.md 를 읽지 못하고 폴백이 쓰였다")
    }

    func testMonthlyPromptComesFromMarkdownNotFallback() {
        let rendered = MonthlyGoalTask.prompt(for: goals, suggestionCount: 3)
        XCTAssertTrue(rendered.contains("[작성 절차"), "monthly_goal.md 를 읽지 못하고 폴백이 쓰였다")
    }

    /// 치환에 실패하면 `{{maxMemoCount}}` 같은 문자열이 그대로 모델에게 간다.
    func testPlaceholdersAreAllSubstituted() {
        let weekly = WeeklyGoalTask.prompt(for: memos, suggestionCount: 3, maxMemoCount: 5)
        XCTAssertFalse(weekly.contains("{{"), "주간 프롬프트에 치환되지 않은 자리표시자가 남았다")
        XCTAssertTrue(weekly.contains("5개 이하로 넣어"))
        XCTAssertTrue(weekly.contains("주간 보고서 초안 작성"))

        let monthly = MonthlyGoalTask.prompt(for: goals, suggestionCount: 2)
        XCTAssertFalse(monthly.contains("{{"), "월간 프롬프트에 치환되지 않은 자리표시자가 남았다")
        XCTAssertTrue(monthly.contains("최대 2개까지"))
        XCTAssertTrue(monthly.contains("주간 리포트 자동화"))
    }

    /// 예산을 넘으면 뒤에서부터 자르되 2개는 남긴다 — 1개짜리는 묶을 수 없기 때문이다.
    func testBudgetTrimsFromTailButKeepsTwo() {
        let items = (0..<20).map {
            WeeklyGoalTask.Memo(
                id: UUID(),
                content: "할일 본문 \($0)",
                icon: "📝",
                date: Date(timeIntervalSince1970: 1_770_000_000)
            )
        }
        let twoMemosBudget = WeeklyGoalTask.prompt(
            for: Array(items.prefix(2)), suggestionCount: 4, maxMemoCount: 5
        ).count + 5
        let selected = WeeklyGoalTask.memosWithinPromptBudget(
            items, suggestionCount: 4, maxMemoCount: 5, budget: twoMemosBudget
        )
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(selected.map(\.id), Array(items.prefix(2)).map(\.id), "앞에서부터 남긴다")
    }
}
