import XCTest
@testable import 호롱호롱

/// 포인트 원장 계산과 적립 정책.
/// 목표 달성 여부가 파생값이라 재적립을 막는 규칙이 이 시스템의 핵심이다.
final class RewardLedgerTests: XCTestCase {
    private func earn(_ amount: Int, goal: UUID? = nil) -> RewardEntrySnapshot {
        RewardEntrySnapshot(amount: amount, kind: .earn, sourceGoalID: goal)
    }

    private func spend(_ amount: Int, goal: UUID? = nil) -> RewardEntrySnapshot {
        RewardEntrySnapshot(amount: -amount, kind: .spend, sourceGoalID: goal)
    }

    // MARK: - 잔액

    func testEmptyLedgerHasZeroBalance() {
        XCTAssertEqual(RewardLedger.balance([]), 0)
    }

    func testBalanceSumsEarnAndSpend() {
        let entries = [earn(10), earn(10), earn(10), spend(25)]
        XCTAssertEqual(RewardLedger.balance(entries), 5)
    }

    func testBalanceCanReachExactlyZero() {
        XCTAssertEqual(RewardLedger.balance([earn(30), spend(30)]), 0)
    }

    // MARK: - 중복 적립·사용 차단

    func testHasClaimedIsTrueOnlyForTheSameGoal() {
        let claimed = UUID()
        let other = UUID()
        let entries = [earn(10, goal: claimed)]

        XCTAssertTrue(RewardLedger.hasClaimed(goalID: claimed, in: entries))
        XCTAssertFalse(RewardLedger.hasClaimed(goalID: other, in: entries))
    }

    /// 사용 이력은 적립으로 세지 않는다. 같은 목표 id라도 종류가 다르면 별개다.
    func testSpendEntryDoesNotCountAsClaim() {
        let goal = UUID()
        XCTAssertFalse(RewardLedger.hasClaimed(goalID: goal, in: [spend(10, goal: goal)]))
        XCTAssertTrue(RewardLedger.hasRedeemed(goalID: goal, in: [spend(10, goal: goal)]))
    }

    func testEarnEntryDoesNotCountAsRedemption() {
        let goal = UUID()
        XCTAssertFalse(RewardLedger.hasRedeemed(goalID: goal, in: [earn(10, goal: goal)]))
    }

    // MARK: - 구매 가능 판정

    /// 가격이 잔액과 정확히 같으면 살 수 있다.
    func testItemPricedExactlyAtBalanceIsAffordable() {
        let items = [
            RewardItemSnapshot(costPoints: 30),
            RewardItemSnapshot(costPoints: 31),
        ]
        let progress = RewardLedger.progress(balance: 30, items: items)

        XCTAssertEqual(progress.affordableCount, 1)
        XCTAssertNil(progress.pointsToNext)
    }

    // MARK: - 호롱불 기름 높이

    func testFillRatioIsZeroWhenTargetIsNotPositive() {
        // 보상 목록이 비면 채울 기준이 없다. 0으로 나누지 않는지 확인한다.
        XCTAssertEqual(RewardLedger.fillRatio(balance: 50, target: 0), 0)
        XCTAssertEqual(RewardLedger.fillRatio(balance: 50, target: -10), 0)
    }

    func testFillRatioClampsBetweenZeroAndOne() {
        XCTAssertEqual(RewardLedger.fillRatio(balance: 0, target: 40), 0)
        XCTAssertEqual(RewardLedger.fillRatio(balance: 20, target: 40), 0.5)
        XCTAssertEqual(RewardLedger.fillRatio(balance: 80, target: 40), 1)
    }

    // MARK: - 진행 상태 (호롱불 + 안내 문구)

    /// 살 수 있는 보상이 있으면 미달 보상을 가리키지 않는다.
    /// 이걸 놓치면 10P 보상을 받을 수 있는데도 "다음 보상까지 40P"라고 말하게 된다.
    func testProgressAnnouncesAffordableRewardInsteadOfNextTarget() {
        let items = [
            RewardItemSnapshot(costPoints: 10),
            RewardItemSnapshot(costPoints: 50),
        ]
        let progress = RewardLedger.progress(balance: 10, items: items)

        XCTAssertEqual(progress.affordableCount, 1)
        XCTAssertTrue(progress.hasAffordableReward)
        XCTAssertNil(progress.pointsToNext)
        XCTAssertEqual(progress.fillRatio, 1)
    }

    /// 보상을 쓰고 잔액이 0이 되면 다시 가장 싼 보상을 목표로 잡는다.
    /// 카탈로그 항목은 소모되지 않으므로 10P 보상이 그대로 다음 목표다.
    func testProgressTargetsCheapestRewardAgainAfterSpending() {
        let items = [
            RewardItemSnapshot(costPoints: 10),
            RewardItemSnapshot(costPoints: 50),
        ]
        let progress = RewardLedger.progress(balance: 0, items: items)

        XCTAssertEqual(progress.affordableCount, 0)
        XCTAssertEqual(progress.pointsToNext, 10)
        XCTAssertEqual(progress.fillRatio, 0)
    }

    func testProgressCountsEveryAffordableReward() {
        let items = [
            RewardItemSnapshot(costPoints: 10),
            RewardItemSnapshot(costPoints: 30),
            RewardItemSnapshot(costPoints: 90),
        ]
        XCTAssertEqual(RewardLedger.progress(balance: 30, items: items).affordableCount, 2)
    }

    func testProgressFillsPartiallyTowardCheapestReward() {
        let items = [RewardItemSnapshot(costPoints: 50)]
        let progress = RewardLedger.progress(balance: 20, items: items)

        XCTAssertEqual(progress.pointsToNext, 30)
        XCTAssertEqual(progress.fillRatio, 0.4, accuracy: 0.0001)
    }

    func testProgressWithEmptyCatalogHasNothingToAimFor() {
        let progress = RewardLedger.progress(balance: 40, items: [])

        XCTAssertEqual(progress.affordableCount, 0)
        XCTAssertNil(progress.pointsToNext)
        XCTAssertEqual(progress.fillRatio, 0)
    }

    func testProgressIgnoresArchivedItems() {
        let items = [
            RewardItemSnapshot(costPoints: 10, isArchived: true),
            RewardItemSnapshot(costPoints: 50),
        ]
        let progress = RewardLedger.progress(balance: 10, items: items)

        XCTAssertEqual(progress.affordableCount, 0)
        XCTAssertEqual(progress.pointsToNext, 40)
    }

    // MARK: - 적립 정책

    private func goal(cadence: String, isComplete: Bool) -> RewardClaimableGoal {
        RewardClaimableGoal(
            id: UUID(),
            title: "주 3회 달리기",
            emoji: "🏃",
            cadence: cadence,
            isComplete: isComplete
        )
    }

    func testFixedPolicyGivesConfiguredPointsForCompletedWeeklyGoal() {
        let policy = FixedWeeklyRewardPolicy(pointsPerGoal: 10)
        XCTAssertEqual(policy.points(forWeeklyGoal: goal(cadence: "주간", isComplete: true)), 10)
    }

    func testFixedPolicyGivesNothingForIncompleteGoal() {
        let policy = FixedWeeklyRewardPolicy(pointsPerGoal: 10)
        XCTAssertEqual(policy.points(forWeeklyGoal: goal(cadence: "주간", isComplete: false)), 0)
    }

    /// 월간 목표는 포인트를 쓰는 쪽이지 쌓는 쪽이 아니다.
    func testFixedPolicyGivesNothingForMonthlyGoal() {
        let policy = FixedWeeklyRewardPolicy(pointsPerGoal: 10)
        XCTAssertEqual(policy.points(forWeeklyGoal: goal(cadence: "월간", isComplete: true)), 0)
    }

    func testFixedPolicyNeverGivesNegativePoints() {
        let policy = FixedWeeklyRewardPolicy(pointsPerGoal: -5)
        XCTAssertEqual(policy.points(forWeeklyGoal: goal(cadence: "주간", isComplete: true)), 0)
    }
}
