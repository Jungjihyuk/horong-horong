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

    // MARK: - 되돌리기 가능 여부

    /// 받은 뒤 아직 쓰지 않았으면 잔액이 적립액을 덮으므로 되돌릴 수 있다.
    func testUnspentClaimCanBeRevoked() {
        let goal = UUID()
        let entries = [earn(10, goal: goal), earn(10)]
        XCTAssertGreaterThanOrEqual(RewardLedger.balance(entries), 10)
    }

    /// 그 포인트로 이미 보상을 받았으면 되돌릴 때 잔액이 음수가 된다.
    func testSpentClaimWouldPushBalanceNegative() {
        let goal = UUID()
        let entries = [earn(10, goal: goal), spend(10)]
        XCTAssertLessThan(RewardLedger.balance(entries), 10)
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
        XCTAssertEqual(progress.pointsToNext, 1)
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

    /// 살 수 있는 보상이 생겨도 게이지는 가장 비싼 보상을 향해 계속 차오른다.
    /// 여기서 1로 못박으면 싼 보상 하나만 있어도 등불이 영영 가득 차 보인다.
    func testProgressKeepsFillingTowardMostExpensiveReward() {
        let items = [
            RewardItemSnapshot(costPoints: 10),
            RewardItemSnapshot(costPoints: 50),
        ]
        let progress = RewardLedger.progress(balance: 10, items: items)

        XCTAssertEqual(progress.affordableCount, 1)
        XCTAssertTrue(progress.hasAffordableReward)
        XCTAssertEqual(progress.pointsToNext, 40)
        XCTAssertEqual(progress.fillRatio, 0.2, accuracy: 0.0001)
    }

    /// 보상을 더 추가해도 가장 비싼 값이 그대로면 게이지가 떨어지지 않는다.
    /// 합계를 기준으로 삼았다면 등록할수록 게이지가 내려가 손해처럼 느껴진다.
    func testAddingCheaperRewardDoesNotDropTheGauge() {
        let before = RewardLedger.progress(balance: 30, items: [RewardItemSnapshot(costPoints: 60)])
        let after = RewardLedger.progress(
            balance: 30,
            items: [RewardItemSnapshot(costPoints: 60), RewardItemSnapshot(costPoints: 20)]
        )

        XCTAssertEqual(before.fillRatio, after.fillRatio, accuracy: 0.0001)
    }

    // MARK: - 눈금

    func testMarksAreSortedByCostAndFlagWhatIsReached() {
        let items = [
            RewardItemSnapshot(emoji: "🎮", title: "게임", costPoints: 80),
            RewardItemSnapshot(emoji: "👛", title: "지갑", costPoints: 10),
            RewardItemSnapshot(emoji: "📱", title: "케이스", costPoints: 50),
        ]
        let marks = RewardLedger.progress(balance: 30, items: items).marks

        XCTAssertEqual(marks.map(\.costPoints), [10, 50, 80])
        XCTAssertEqual(marks.map(\.isReached), [true, false, false])
        XCTAssertEqual(marks.map(\.emoji), ["👛", "📱", "🎮"])
    }

    /// 가장 비싼 보상이 눈금 꼭대기(1.0)에 놓인다.
    func testMarkHeightsAreRelativeToTheMostExpensiveReward() {
        let items = [
            RewardItemSnapshot(costPoints: 20),
            RewardItemSnapshot(costPoints: 80),
        ]
        let marks = RewardLedger.progress(balance: 0, items: items).marks

        XCTAssertEqual(marks[0].heightRatio, 0.25, accuracy: 0.0001)
        XCTAssertEqual(marks[1].heightRatio, 1, accuracy: 0.0001)
    }

    func testMarksExcludeArchivedRewards() {
        let items = [
            RewardItemSnapshot(costPoints: 10, isArchived: true),
            RewardItemSnapshot(costPoints: 50),
        ]
        XCTAssertEqual(RewardLedger.progress(balance: 0, items: items).marks.map(\.costPoints), [50])
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
