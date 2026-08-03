import XCTest
@testable import 호롱호롱

/// 주차별 월간 목표 진행률과 월 경계 규칙.
/// 2026년 7월은 수요일에 시작해 5주차까지 있고, 1주차가 수·목·금·토·일 5일뿐인 부분 주차다.
final class AchievementMonthlyStatsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func july2026() -> Date { date(2026, 7, 15) }

    // MARK: - 월 경계

    func testGoalCreatedNextMonthIsNotShownInEarlierMonth() {
        let julyStart = AchievementMonthlyStats.firstDayOfMonth(for: july2026(), calendar: calendar)

        XCTAssertFalse(
            AchievementMonthlyStats.goalBelongs(
                toMonthStarting: julyStart,
                createdAt: date(2026, 8, 2),
                completedAt: nil,
                now: date(2026, 8, 3),
                calendar: calendar
            )
        )
    }

    func testUnfinishedGoalCarriesOverToLaterMonths() {
        let created = date(2026, 7, 10)
        let now = date(2026, 8, 3)

        for month in 7...8 {
            let monthStart = AchievementMonthlyStats.firstDayOfMonth(for: date(2026, month, 1), calendar: calendar)
            XCTAssertTrue(
                AchievementMonthlyStats.goalBelongs(
                    toMonthStarting: monthStart,
                    createdAt: created,
                    completedAt: nil,
                    now: now,
                    calendar: calendar
                ),
                "\(month)월에 이월되어 보여야 한다"
            )
        }
    }

    func testCompletedGoalStopsAtTheMonthItWasFinished() {
        let created = date(2026, 7, 10)
        let completed = date(2026, 8, 20)
        let now = date(2026, 9, 5)

        func belongs(toMonth month: Int) -> Bool {
            AchievementMonthlyStats.goalBelongs(
                toMonthStarting: AchievementMonthlyStats.firstDayOfMonth(for: date(2026, month, 1), calendar: calendar),
                createdAt: created,
                completedAt: completed,
                now: now,
                calendar: calendar
            )
        }

        XCTAssertTrue(belongs(toMonth: 7))
        XCTAssertTrue(belongs(toMonth: 8))
        XCTAssertFalse(belongs(toMonth: 9), "완료한 달 다음부터는 보이지 않아야 한다")
    }

    func testGoalFinishedBeforeItWasCreatedStillShowsInItsCreatedMonth() {
        let monthStart = AchievementMonthlyStats.firstDayOfMonth(for: july2026(), calendar: calendar)

        XCTAssertTrue(
            AchievementMonthlyStats.goalBelongs(
                toMonthStarting: monthStart,
                createdAt: date(2026, 7, 10),
                completedAt: date(2026, 6, 1),
                now: date(2026, 8, 3),
                calendar: calendar
            )
        )
    }

    // MARK: - 주차별 누적 달성률

    func testWeekProgressAccumulatesAndKeepsQuietWeeksFlat() {
        let goals = [
            AchievementMonthlyStats.Goal(total: 2, completions: [date(2026, 7, 3), date(2026, 7, 31)]),
            AchievementMonthlyStats.Goal(total: 5, completions: [date(2026, 7, 3), date(2026, 7, 15), date(2026, 7, 30)]),
            AchievementMonthlyStats.Goal(total: 5, completions: [date(2026, 7, 3), date(2026, 7, 30), date(2026, 7, 31)])
        ]

        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: july2026(),
            goals: goals,
            now: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.total), Array(repeating: 12, count: 5), "분모는 다섯 주 모두 목표량 합으로 고정된다")
        XCTAssertEqual(rows.map(\.completed), [3, 3, 4, 4, 8])
        XCTAssertEqual(rows.map(\.percentText), ["25%", "25%", "33%", "33%", "67%"])
    }

    func testLastWeekMatchesTheGoalListTotals() {
        let goals = [
            AchievementMonthlyStats.Goal(total: 2, completions: [date(2026, 7, 3)]),
            AchievementMonthlyStats.Goal(total: 1, completions: [date(2026, 7, 20)]),
            AchievementMonthlyStats.Goal(total: 5, completions: [date(2026, 7, 6), date(2026, 7, 7), date(2026, 7, 8)])
        ]

        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: july2026(),
            goals: goals,
            now: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(rows.last?.completed, 5, "목록의 1 + 1 + 3과 같아야 한다")
        XCTAssertEqual(rows.last?.total, 8, "목록의 2 + 1 + 5와 같아야 한다")
    }

    func testPartialFirstWeekCountsOnlyItsOwnDays() {
        // 7월 1주차는 1일(수)~5일(일)뿐이다. 6일 완료분은 2주차부터 잡혀야 한다.
        let goals = [AchievementMonthlyStats.Goal(total: 2, completions: [date(2026, 7, 5), date(2026, 7, 6)])]

        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: july2026(),
            goals: goals,
            now: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(rows[0].completed, 1)
        XCTAssertEqual(rows[1].completed, 2)
    }

    func testCompletionsAreCappedByTheGoalTarget() {
        let goals = [AchievementMonthlyStats.Goal(total: 2, completions: (1...5).map { date(2026, 7, $0) })]

        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: july2026(),
            goals: goals,
            now: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.completed), Array(repeating: 2, count: 5), "100%를 넘길 수 없다")
    }

    func testCarriedOverGoalKeepsWhatItAlreadyAchieved() {
        // 7월에 만들어 8월로 이월된 목표. 7월에 이룬 몫은 8월 1주차부터 이미 반영된다.
        let goals = [AchievementMonthlyStats.Goal(total: 4, completions: [date(2026, 7, 20), date(2026, 8, 25)])]

        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: date(2026, 8, 15),
            goals: goals,
            now: date(2026, 8, 31),
            calendar: calendar
        )

        XCTAssertEqual(rows.first?.completed, 1)
        XCTAssertEqual(rows.last?.completed, 2)
    }

    func testNoGoalsMeansNoDenominatorInsteadOfZeroPercentBars() {
        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: july2026(),
            goals: [],
            now: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.total), Array(repeating: 0, count: 5))
        XCTAssertEqual(rows.map(\.progress), Array(repeating: 0, count: 5))
    }

    func testOngoingMonthShowsOnlyThroughTheCurrentWeek() {
        // 2026년 8월 3일은 월요일 시작 달력의 2주차다.
        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: date(2026, 8, 1),
            goals: [AchievementMonthlyStats.Goal(total: 1, completions: [])],
            now: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.week), [1, 2], "아직 오지 않은 3주차 이후는 표시하지 않는다")
        XCTAssertEqual(rows.filter(\.isCurrent).map(\.week), [2])
    }

    func testSixthCalendarRowIsFoldedIntoTheFifthWeek() {
        // 2026년 8월 31일은 달력의 여섯 번째 줄이지만 월간 통계에는 별도 6주차를 만들지 않는다.
        let rows = AchievementMonthlyStats.weekProgress(
            forMonth: date(2026, 8, 1),
            goals: [AchievementMonthlyStats.Goal(total: 1, completions: [date(2026, 8, 31)])],
            now: date(2026, 9, 1),
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.week), [1, 2, 3, 4, 5])
        XCTAssertEqual(rows.last?.completed, 1, "마지막 날의 완료분은 5주차에 포함한다")
    }

    // MARK: - 이번 주 표시

    func testCurrentWeekIsMarkedOnlyInTheOngoingMonth() {
        let ongoing = AchievementMonthlyStats.weekProgress(
            forMonth: date(2026, 7, 1),
            goals: [AchievementMonthlyStats.Goal(total: 1, completions: [])],
            now: date(2026, 7, 15),
            calendar: calendar
        )
        XCTAssertEqual(ongoing.filter(\.isCurrent).map(\.week), [3])

        let past = AchievementMonthlyStats.weekProgress(
            forMonth: date(2026, 7, 1),
            goals: [AchievementMonthlyStats.Goal(total: 1, completions: [])],
            now: date(2026, 8, 3),
            calendar: calendar
        )
        XCTAssertTrue(past.allSatisfy { !$0.isCurrent })
    }

    func testWeekIndexFollowsTheCalendarRows() {
        XCTAssertEqual(AchievementMonthlyStats.weekIndex(for: date(2026, 7, 1), calendar: calendar), 1)
        XCTAssertEqual(AchievementMonthlyStats.weekIndex(for: date(2026, 7, 5), calendar: calendar), 1)
        XCTAssertEqual(AchievementMonthlyStats.weekIndex(for: date(2026, 7, 6), calendar: calendar), 2)
        XCTAssertEqual(AchievementMonthlyStats.weekIndex(for: date(2026, 7, 31), calendar: calendar), 5)
    }
}
