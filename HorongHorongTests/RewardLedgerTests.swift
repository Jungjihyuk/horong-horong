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

    func testAffordableIncludesItemPricedExactlyAtBalance() {
        let items = [
            RewardItemSnapshot(costPoints: 30),
            RewardItemSnapshot(costPoints: 31),
        ]
        let affordable = RewardLedger.affordable(items, balance: 30)

        XCTAssertEqual(affordable.map(\.costPoints), [30])
    }

    func testAffordableExcludesArchivedItems() {
        let items = [
            RewardItemSnapshot(costPoints: 10, isArchived: true),
            RewardItemSnapshot(costPoints: 10),
        ]
        XCTAssertEqual(RewardLedger.affordable(items, balance: 50).count, 1)
    }

    // MARK: - 다음 보상까지

    func testPointsToNextRewardUsesCheapestUnreachableItem() {
        let items = [
            RewardItemSnapshot(costPoints: 100),
            RewardItemSnapshot(costPoints: 40),
            RewardItemSnapshot(costPoints: 10),
        ]
        // 잔액 25 → 40짜리가 가장 싼 미달 보상이므로 15P 남았다.
        XCTAssertEqual(RewardLedger.pointsToNextReward(items: items, balance: 25), 15)
    }

    func testPointsToNextRewardIsNilWhenEverythingIsAffordable() {
        let items = [RewardItemSnapshot(costPoints: 10)]
        XCTAssertNil(RewardLedger.pointsToNextReward(items: items, balance: 10))
    }

    func testPointsToNextRewardIsNilWithEmptyCatalog() {
        XCTAssertNil(RewardLedger.pointsToNextReward(items: [], balance: 0))
    }

    func testPointsToNextRewardIgnoresArchivedItems() {
        let items = [
            RewardItemSnapshot(costPoints: 20, isArchived: true),
            RewardItemSnapshot(costPoints: 50),
        ]
        XCTAssertEqual(RewardLedger.pointsToNextReward(items: items, balance: 10), 40)
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
