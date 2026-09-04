import SwiftData
import XCTest
@testable import 호롱호롱

/// **가짜가 아니라 진짜 SwiftData 로** 원장을 검사한다.
///
/// `RewardViewModelTests` 는 가짜 저장소를 쓴다 — 화면의 판단은 검사하지만, 그 가짜가
/// 실제 구현과 어긋나면 둘 다 통과하면서 실기만 틀린다. 저장·조회·중복 방지가 실제로
/// 도는지는 여기서 본다.
@MainActor
final class SwiftDataRewardRepositoryTests: XCTestCase {
    /// **컨테이너를 돌려준다.** 컨텍스트만 돌려주면 컨테이너가 해제되어 테스트 프로세스가
    /// 조용히 죽는다 — 증상이 술어 번역 실패와 똑같아 원인을 찾기 어렵다.
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func goal(
        _ cadence: String = "주간",
        complete: Bool = true,
        id: UUID = UUID()
    ) -> RewardClaimableGoal {
        RewardClaimableGoal(id: id, title: "목표", emoji: "🎯", cadence: cadence, isComplete: complete)
    }

    private let policy = FixedWeeklyRewardPolicy(pointsPerGoal: 30)

    // MARK: - 적립

    func testClaimAddsPoints() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        let points = repository.claim(goal(), policy: policy)

        XCTAssertEqual(points, 30)
        XCTAssertEqual(repository.balance(), 30)
    }

    /// 목표 하나당 적립은 평생 한 번이다. 할 일을 뺐다 붙이면 완료 상태가 오가기 때문이다.
    func testSameGoalCannotBeClaimedTwice() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let weekly = goal()

        repository.claim(weekly, policy: policy)
        let second = repository.claim(weekly, policy: policy)

        XCTAssertNil(second)
        XCTAssertEqual(repository.balance(), 30)
        XCTAssertTrue(repository.hasClaimed(goalID: weekly.id))
    }

    func testIncompleteGoalIsNotClaimed() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        XCTAssertNil(repository.claim(goal(complete: false), policy: policy))
        XCTAssertEqual(repository.balance(), 0)
    }

    /// 월간 목표에는 주간 적립 정책이 포인트를 주지 않는다.
    func testMonthlyGoalEarnsNothingFromWeeklyPolicy() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        XCTAssertNil(repository.claim(goal("월간"), policy: policy))
    }

    // MARK: - 되돌리기

    func testRevokeRemovesPoints() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let weekly = goal()
        repository.claim(weekly, policy: policy)

        let result = repository.revokeClaim(goalID: weekly.id)

        XCTAssertEqual(try result.get(), 30)
        XCTAssertEqual(repository.balance(), 0)
        XCTAssertFalse(repository.hasClaimed(goalID: weekly.id))
    }

    func testRevokeWithoutClaimFails() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        guard case .failure(let error) = repository.revokeClaim(goalID: UUID()) else {
            return XCTFail("받은 적이 없으면 실패해야 한다")
        }
        XCTAssertEqual(error, .notClaimed)
    }

    /// **이미 그 포인트로 보상을 받았으면 되돌릴 수 없다.** 잔액이 음수가 되기 때문이다.
    func testRevokeAfterSpendingFails() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let weekly = goal()
        repository.claim(weekly, policy: policy)
        let item = repository.addCatalogItem(title: "커피", emoji: "☕️", costPoints: 25, note: "")
        _ = repository.redeem(itemID: item.id, forMonthlyGoal: goal("월간"))

        guard case .failure(let error) = repository.revokeClaim(goalID: weekly.id) else {
            return XCTFail("이미 쓴 포인트는 되돌릴 수 없다")
        }
        XCTAssertEqual(error, .alreadySpent(shortBy: 25), "30P 중 25P 를 써서 5P 만 남았다")
        XCTAssertEqual(repository.balance(), 5)
    }

    // MARK: - 사용

    func testRedeemDeductsAndRecordsSnapshot() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        repository.claim(goal(), policy: policy)
        let item = repository.addCatalogItem(title: "커피", emoji: "☕️", costPoints: 20, note: "")
        let monthly = goal("월간")

        let entry = try repository.redeem(itemID: item.id, forMonthlyGoal: monthly).get()

        XCTAssertEqual(repository.balance(), 10)
        XCTAssertEqual(entry.amount, -20)
        XCTAssertEqual(entry.note, "☕️ 커피", "원본이 지워져도 남을 제목 스냅샷")
        XCTAssertTrue(repository.hasRedeemed(goalID: monthly.id))
    }

    func testRedeemTwiceWithSameGoalFails() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        repository.claim(goal(), policy: policy)
        let item = repository.addCatalogItem(title: "커피", emoji: "☕️", costPoints: 10, note: "")
        let monthly = goal("월간")
        _ = repository.redeem(itemID: item.id, forMonthlyGoal: monthly)

        guard case .failure(let error) = repository.redeem(itemID: item.id, forMonthlyGoal: monthly) else {
            return XCTFail("같은 목표로 두 번 받을 수 없다")
        }
        XCTAssertEqual(error, .alreadyRedeemed)
        XCTAssertEqual(repository.balance(), 20)
    }

    func testRedeemWithoutEnoughPointsReportsShortfall() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let item = repository.addCatalogItem(title: "영화", emoji: "🎬", costPoints: 50, note: "")

        guard case .failure(let error) = repository.redeem(itemID: item.id, forMonthlyGoal: goal("월간")) else {
            return XCTFail("잔액이 모자라면 거절해야 한다")
        }
        XCTAssertEqual(error, .insufficientBalance(shortBy: 50))
    }

    func testRedeemRequiresCompleteGoal() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        repository.claim(goal(), policy: policy)
        let item = repository.addCatalogItem(title: "커피", emoji: "☕️", costPoints: 10, note: "")

        guard case .failure(let error) = repository.redeem(
            itemID: item.id,
            forMonthlyGoal: goal("월간", complete: false)
        ) else {
            return XCTFail("미달성 목표로는 받을 수 없다")
        }
        XCTAssertEqual(error, .goalNotComplete)
    }

    // MARK: - 보상 목록

    func testCatalogRoundTrips() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        let item = repository.addCatalogItem(title: "커피", emoji: "☕️", costPoints: 20, note: "메모")
        XCTAssertEqual(repository.catalogItems().map(\.title), ["커피"])

        repository.updateCatalogItem(id: item.id, title: "라떼", emoji: "🥛", costPoints: 25, note: "")
        let updated = try XCTUnwrap(repository.catalogItems().first)
        XCTAssertEqual(updated.title, "라떼")
        XCTAssertEqual(updated.costPoints, 25)

        repository.deleteCatalogItem(id: item.id)
        XCTAssertTrue(repository.catalogItems().isEmpty)
    }

    /// **보상을 지워도 지난 이력은 남는다.** 원장은 제목 스냅샷을 들고 있다.
    func testDeletingCatalogItemKeepsLedgerHistory() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        repository.claim(goal(), policy: policy)
        let item = repository.addCatalogItem(title: "커피", emoji: "☕️", costPoints: 20, note: "")
        _ = repository.redeem(itemID: item.id, forMonthlyGoal: goal("월간"))

        repository.deleteCatalogItem(id: item.id)

        XCTAssertTrue(repository.catalogItems().isEmpty)
        XCTAssertEqual(repository.entries().filter { $0.kind == .spend }.map(\.note), ["☕️ 커피"])
        XCTAssertEqual(repository.balance(), 10, "잔액은 그대로")
    }

    /// 새 항목은 목록 끝에 붙는다.
    func testAddedItemsKeepInsertionOrder() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        repository.addCatalogItem(title: "하나", emoji: "🎁", costPoints: 10, note: "")
        repository.addCatalogItem(title: "둘", emoji: "🎁", costPoints: 10, note: "")

        XCTAssertEqual(repository.catalogItems().map(\.title), ["하나", "둘"])
    }

    // MARK: - 갱신 알림

    /// 쓰기마다 알림이 나가야 다른 화면이 옛 값을 안 본다.
    func testWritePostsChangeNotification() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let notified = expectation(
            forNotification: SwiftDataRewardRepository.didChangeNotification,
            object: nil
        )

        repository.claim(goal(), policy: policy)

        wait(for: [notified], timeout: 1)
    }
    // MARK: - 실패 마감 패널티

    private func claimableWeekly(_ id: UUID, title: String = "주간 기록") -> RewardClaimableGoal {
        RewardClaimableGoal(id: id, title: title, emoji: "🎯", cadence: "주간", isComplete: true)
    }

    func testPenalizeChargesOnceAndLowersBalance() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let earned = claimableWeekly(UUID())
        repository.claim(earned, policy: FixedWeeklyRewardPolicy(pointsPerGoal: 20))
        let failed = UUID()

        let first = repository.penalize(goalID: failed, nominalPoints: 8, note: "🎯 주간 기록", at: Date())
        let second = repository.penalize(goalID: failed, nominalPoints: 8, note: "🎯 주간 기록", at: Date())

        XCTAssertEqual(first?.charged, 8)
        XCTAssertEqual(first?.forgiven, 0)
        XCTAssertNil(second, "같은 목표를 두 번 깎으면 안 된다")
        XCTAssertEqual(repository.balance(), 12)
        XCTAssertTrue(repository.hasPenalized(goalID: failed))
    }

    /// 잔액은 0 에서 바닥이다. 빚을 지고 시작하면 회복이 멀어진다.
    func testPenaltyStopsAtZeroBalanceAndRecordsWhatItCouldNotTake() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let earned = claimableWeekly(UUID())
        repository.claim(earned, policy: FixedWeeklyRewardPolicy(pointsPerGoal: 3))
        let failed = UUID()

        let result = repository.penalize(goalID: failed, nominalPoints: 10, note: "🎯 주간 기록", at: Date())

        XCTAssertEqual(result?.nominal, 10)
        XCTAssertEqual(result?.charged, 3)
        XCTAssertEqual(result?.forgiven, 7)
        XCTAssertEqual(repository.balance(), 0)
        // 왜 10P 가 아니라 3P 만 깎였는지가 이력에 남아야 한다.
        let note = repository.entries().first { $0.kind == .penalty }?.note
        XCTAssertEqual(note?.contains("명목 10P 중 3P"), true)
    }

    func testPenaltyIsSkippedWhenBalanceIsEmpty() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)

        let result = repository.penalize(goalID: UUID(), nominalPoints: 5, note: "🎯", at: Date())

        XCTAssertNil(result)
        XCTAssertEqual(repository.balance(), 0)
    }

    /// 같은 목표로 포인트를 받은 적이 있으면 깎지 않는다 — 주고 또 뺏으면 이중 장부다.
    func testGoalThatAlreadyEarnedIsNeverPenalized() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        let goal = claimableWeekly(UUID())
        repository.claim(goal, policy: FixedWeeklyRewardPolicy(pointsPerGoal: 20))

        let result = repository.penalize(goalID: goal.id, nominalPoints: 5, note: "🎯", at: Date())

        XCTAssertNil(result)
        XCTAssertEqual(repository.balance(), 20)
    }

    func testRevokePenaltyRestoresThePoints() throws {
        let container = try makeContainer()
        let repository = SwiftDataRewardRepository(context: container.mainContext)
        repository.claim(claimableWeekly(UUID()), policy: FixedWeeklyRewardPolicy(pointsPerGoal: 20))
        let failed = UUID()
        repository.penalize(goalID: failed, nominalPoints: 8, note: "🎯", at: Date())

        let restored = repository.revokePenalty(goalID: failed)

        XCTAssertEqual(restored, 8)
        XCTAssertEqual(repository.balance(), 20)
        XCTAssertFalse(repository.hasPenalized(goalID: failed))
    }

}
