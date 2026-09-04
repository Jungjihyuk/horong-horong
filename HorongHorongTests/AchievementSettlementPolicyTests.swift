import XCTest
@testable import 호롱호롱

/// 마감을 넘긴 목표의 정산 단계 계산.
///
/// 「자정이 지나면 답이 달라지는」 계산이라 고정 달력·고정 시각으로만 검사한다.
/// 2026년 9월 7일은 월요일이다.
final class AchievementSettlementPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func state(
        cadence: String = "주간",
        dueDate: Date? = nil,
        createdAt: Date,
        completedAt: Date? = nil,
        closedAt: Date? = nil,
        now: Date
    ) -> AchievementSettlementState {
        AchievementSettlementPolicy.state(
            cadence: cadence,
            dueDate: dueDate,
            createdAt: createdAt,
            completedAt: completedAt,
            closedAt: closedAt,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - 암묵적 마감 (마감일을 안 넣은 목표)

    func testWeeklyGoalWithoutDueDateEndsAtNextMonday() {
        // 2026-09-07(월) 주에 만든 목표 → 2026-09-14(월) 0시가 경계
        let deadline = AchievementSettlementPolicy.implicitDeadline(
            cadence: "주간",
            createdAt: date(2026, 9, 9),
            calendar: calendar
        )

        XCTAssertEqual(deadline, date(2026, 9, 14, 0))
    }

    func testMonthlyGoalWithoutDueDateEndsAtFirstOfNextMonth() {
        let deadline = AchievementSettlementPolicy.implicitDeadline(
            cadence: "월간",
            createdAt: date(2026, 9, 9),
            calendar: calendar
        )

        XCTAssertEqual(deadline, date(2026, 10, 1, 0))
    }

    func testNonSettleableCadenceHasNoDeadline() {
        for cadence in ["연간", "역할", "비전"] {
            XCTAssertNil(
                AchievementSettlementPolicy.effectiveDeadline(
                    cadence: cadence,
                    dueDate: date(2026, 9, 1),
                    createdAt: date(2026, 9, 1),
                    calendar: calendar
                ),
                "\(cadence) 은 정산 대상이 아니다"
            )
        }
    }

    /// 마감일은 «그 날까지» 라는 뜻이라 그 날이 다 지나야 넘긴 것이다.
    func testDueDateBoundaryIsTheEndOfThatDay() {
        let deadline = AchievementSettlementPolicy.effectiveDeadline(
            cadence: "주간",
            dueDate: date(2026, 9, 9, 15),
            createdAt: date(2026, 9, 7),
            calendar: calendar
        )

        XCTAssertEqual(deadline, date(2026, 9, 10, 0))
    }

    // MARK: - 단계 전이 (마감일 없는 주간 목표)

    func testWeeklyGoalWithoutDueDateWalksOpenAwaitingExpired() {
        let created = date(2026, 9, 9) // 9/7 주

        XCTAssertEqual(state(createdAt: created, now: date(2026, 9, 11)), .open)

        // 다음 주(9/14~) 내내 정산 대기 — 만회할 기간이다
        let awaiting = state(createdAt: created, now: date(2026, 9, 16))
        XCTAssertTrue(awaiting.isAwaiting)
        XCTAssertEqual(awaiting.deadline, date(2026, 9, 14, 0))

        // 그 다음 주 월요일부터 자동 마감 대상
        XCTAssertTrue(state(createdAt: created, now: date(2026, 9, 21, 0)).isExpired)
    }

    /// 마감(일요일 끝)과 유예 종료가 같은 순간이면 고를 틈이 사라진다. 한 주기를 더 준다.
    func testGraceLastsThroughTheFollowingWeek() {
        let created = date(2026, 9, 9)
        let deadline = date(2026, 9, 14, 0)

        let grace = AchievementSettlementPolicy.graceEnd(
            after: deadline,
            cadence: "주간",
            calendar: calendar
        )

        XCTAssertEqual(grace, date(2026, 9, 21, 0))
        XCTAssertTrue(state(createdAt: created, now: date(2026, 9, 20, 23)).isAwaiting)
    }

    // MARK: - 단계 전이 (마감일을 넣은 주간 목표)

    func testWeeklyGoalWithMidWeekDueDateStaysAwaitingThroughNextWeek() {
        let created = date(2026, 9, 7)
        let due = date(2026, 9, 9) // 수요일

        XCTAssertEqual(state(dueDate: due, createdAt: created, now: date(2026, 9, 9, 23)), .open)
        XCTAssertTrue(state(dueDate: due, createdAt: created, now: date(2026, 9, 10, 1)).isAwaiting)
        XCTAssertTrue(state(dueDate: due, createdAt: created, now: date(2026, 9, 17)).isAwaiting)
        XCTAssertTrue(state(dueDate: due, createdAt: created, now: date(2026, 9, 21, 0)).isExpired)
    }

    // MARK: - 월 경계

    func testMonthlyGoalGraceRunsThroughTheFollowingMonth() {
        let created = date(2026, 9, 9)

        XCTAssertEqual(state(cadence: "월간", createdAt: created, now: date(2026, 9, 30)), .open)
        XCTAssertTrue(state(cadence: "월간", createdAt: created, now: date(2026, 10, 20)).isAwaiting)
        XCTAssertTrue(state(cadence: "월간", createdAt: created, now: date(2026, 11, 1, 0)).isExpired)
    }

    /// 12월 목표의 유예는 다음 해 1월이 끝날 때까지다.
    func testMonthlyGoalCrossesYearBoundary() {
        let created = date(2026, 12, 10)

        let grace = AchievementSettlementPolicy.graceEnd(
            after: date(2027, 1, 1, 0),
            cadence: "월간",
            calendar: calendar
        )

        XCTAssertEqual(grace, date(2027, 2, 1, 0))
        XCTAssertTrue(state(cadence: "월간", createdAt: created, now: date(2027, 1, 20)).isAwaiting)
        XCTAssertTrue(state(cadence: "월간", createdAt: created, now: date(2027, 2, 1, 0)).isExpired)
    }

    /// 2월은 28/29일로 끝나므로 날짜를 더하는 방식이면 틀린다.
    func testFebruaryMonthlyGoalUsesMonthArithmetic() {
        let deadline = AchievementSettlementPolicy.implicitDeadline(
            cadence: "월간",
            createdAt: date(2028, 2, 10),
            calendar: calendar
        )

        XCTAssertEqual(deadline, date(2028, 3, 1, 0))
    }

    // MARK: - 이미 닫힌 목표

    func testCompletedGoalIsNeverSettled() {
        let created = date(2026, 9, 9)

        XCTAssertEqual(
            state(createdAt: created, completedAt: date(2026, 9, 10), now: date(2026, 10, 1)),
            .closed
        )
    }

    func testClosedGoalIsNeverSettledAgain() {
        let created = date(2026, 9, 9)

        XCTAssertEqual(
            state(createdAt: created, closedAt: date(2026, 9, 21), now: date(2026, 12, 1)),
            .closed
        )
    }

    // MARK: - 패널티 크기

    func testWeeklyPenaltyIsBasePointsTimesRatio() {
        XCTAssertEqual(
            AchievementSettlementPolicy.penaltyPoints(cadence: "주간", basePoints: 20, ratio: 0.5),
            10
        )
    }

    /// 월간은 보상 교환 자격을 잃는 것으로 갈음한다. 주간이 이미 깎였는데 또 깎으면 이중 처벌이다.
    func testMonthlyGoalHasNoPointPenalty() {
        XCTAssertEqual(
            AchievementSettlementPolicy.penaltyPoints(cadence: "월간", basePoints: 20, ratio: 0.5),
            0
        )
    }

    func testPenaltyRatioIsClampedAndNeverNegative() {
        XCTAssertEqual(
            AchievementSettlementPolicy.penaltyPoints(cadence: "주간", basePoints: 20, ratio: 4),
            20
        )
        XCTAssertEqual(
            AchievementSettlementPolicy.penaltyPoints(cadence: "주간", basePoints: 20, ratio: -1),
            0
        )
    }

    // MARK: - 표시용 날짜

    func testDeadlineDayStepsBackToTheLastDayInside() {
        let day = AchievementSettlementPolicy.deadlineDay(
            for: date(2026, 9, 14, 0),
            calendar: calendar
        )

        XCTAssertEqual(day, date(2026, 9, 13, 0))
    }
    // MARK: - 「이번 주에 다시」

    private func goalDetail(cadence: String = "주간", linkedMemoIDs: [UUID] = []) -> AchievementGoalDetail {
        AchievementGoalDetail(
            id: UUID(), title: "주간 기록", emoji: "📓", cadence: cadence, rule: "주 5회",
            targetCount: 5, targetValueText: "5회", periodText: "이번 주", dueDate: date(2026, 9, 13),
            rewardText: "", colorHex: "#E87333", roleName: "기록자", vision: "매일 남긴다",
            yearGoal: nil, quarterGoal: nil, monthGoal: "9월 기록", linkedMemoIDs: linkedMemoIDs,
            createdAt: date(2026, 9, 7), updatedAt: date(2026, 9, 7),
            completedAt: nil, closedAt: date(2026, 9, 21), closedReason: .expired
        )
    }

    /// 복제본은 이번 주기 마감을 갖고, 연결한 할일을 그대로 데려온다.
    func testRetryDraftMovesDeadlineToTheCurrentPeriodAndKeepsTodos() {
        let memoID = UUID()

        let draft = AchievementSettlementPolicy.retryDraft(
            from: goalDetail(linkedMemoIDs: [memoID]),
            now: date(2026, 9, 23),
            calendar: calendar
        )

        XCTAssertEqual(draft.title, "주간 기록")
        XCTAssertEqual(draft.linkedMemoIDs, [memoID])
        // 9/23 은 9/21(월) 주 → 마감은 그 주 일요일 9/27
        XCTAssertEqual(draft.dueDate, date(2026, 9, 27, 0))
    }

    /// 복제본은 «직접 만든 목표» 다. 추천 출처를 물려주면 채택률이 부풀어 오른다.
    func testRetryDraftDropsSuggestionProvenance() {
        let draft = AchievementSettlementPolicy.retryDraft(
            from: goalDetail(),
            now: date(2026, 9, 23),
            calendar: calendar
        )

        XCTAssertNil(draft.sourceRunID)
        XCTAssertNil(draft.sourceSuggestionID)
    }

    func testRetryDraftForMonthlyGoalUsesEndOfMonth() {
        let draft = AchievementSettlementPolicy.retryDraft(
            from: goalDetail(cadence: "월간"),
            now: date(2026, 9, 23),
            calendar: calendar
        )

        XCTAssertEqual(draft.dueDate, date(2026, 9, 30, 0))
    }

}
