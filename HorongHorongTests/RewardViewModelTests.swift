import XCTest
@testable import 호롱호롱

/// **저장소 없이** 보상 탭의 규칙을 검사한다.
@MainActor
final class RewardViewModelTests: XCTestCase {
    /// 가짜 저장소. 실제 구현과 같은 규칙(중복 적립·사용 금지, 잔액 부족 거절)을 지킨다.
    private final class FakeRepository: RewardRepository {
        var storedEntries: [RewardEntry] = []
        var storedItems: [RewardItem] = []
        private(set) var reloadCount = 0

        func entries() -> [RewardEntry] { reloadCount += 1; return storedEntries }
        func catalogItems() -> [RewardItem] { storedItems }
        func balance() -> Int { RewardLedger.balance(storedEntries.map(\.snapshot)) }
        func hasClaimed(goalID: UUID) -> Bool {
            RewardLedger.hasClaimed(goalID: goalID, in: storedEntries.map(\.snapshot))
        }
        func hasRedeemed(goalID: UUID) -> Bool {
            RewardLedger.hasRedeemed(goalID: goalID, in: storedEntries.map(\.snapshot))
        }

        func hasPenalized(goalID: UUID) -> Bool {
            RewardLedger.hasPenalized(goalID: goalID, in: storedEntries.map(\.snapshot))
        }

        @discardableResult
        func penalize(goalID: UUID, nominalPoints: Int, note: String, at date: Date) -> RewardPenaltyResult? {
            guard nominalPoints > 0, !hasPenalized(goalID: goalID), !hasClaimed(goalID: goalID) else { return nil }
            let charged = min(nominalPoints, max(0, balance()))
            guard charged > 0 else { return nil }
            storedEntries.append(
                RewardEntry(
                    id: UUID(),
                    amount: -charged,
                    kind: .penalty,
                    sourceGoalID: goalID,
                    catalogItemID: nil,
                    note: note,
                    occurredAt: date
                )
            )
            return RewardPenaltyResult(nominal: nominalPoints, charged: charged, forgiven: nominalPoints - charged)
        }

        @discardableResult
        func revokePenalty(goalID: UUID) -> Int? {
            guard let index = storedEntries.firstIndex(where: { $0.kind == .penalty && $0.sourceGoalID == goalID }) else {
                return nil
            }
            let restored = -storedEntries[index].amount
            storedEntries.remove(at: index)
            return restored
        }

        @discardableResult
        func claim(_ goal: RewardClaimableGoal, policy: RewardPointPolicy) -> Int? {
            guard goal.isComplete, !hasClaimed(goalID: goal.id) else { return nil }
            let points = policy.points(forWeeklyGoal: goal)
            guard points > 0 else { return nil }
            append(amount: points, kind: .earn, sourceGoalID: goal.id, note: goal.title)
            return points
        }

        func revokeClaim(goalID: UUID) -> Result<Int, RewardRevokeError> {
            guard let entry = storedEntries.first(where: { $0.kind == .earn && $0.sourceGoalID == goalID }) else {
                return .failure(.notClaimed)
            }
            let current = balance()
            guard current >= entry.amount else {
                return .failure(.alreadySpent(shortBy: entry.amount - current))
            }
            storedEntries.removeAll { $0.id == entry.id }
            return .success(entry.amount)
        }

        func redeem(itemID: UUID, forMonthlyGoal goal: RewardClaimableGoal) -> Result<RewardEntry, RewardRedeemError> {
            guard goal.isComplete else { return .failure(.goalNotComplete) }
            guard !hasRedeemed(goalID: goal.id) else { return .failure(.alreadyRedeemed) }
            guard let item = storedItems.first(where: { $0.id == itemID }) else { return .failure(.goalNotComplete) }
            let current = balance()
            guard current >= item.costPoints else {
                return .failure(.insufficientBalance(shortBy: item.costPoints - current))
            }
            let entry = append(
                amount: -item.costPoints, kind: .spend,
                sourceGoalID: goal.id, note: "\(item.emoji) \(item.title)"
            )
            return .success(entry)
        }

        @discardableResult
        func addCatalogItem(title: String, emoji: String, costPoints: Int, note: String) -> RewardItem {
            let item = RewardItem(
                id: UUID(), title: title, emoji: emoji, costPoints: costPoints,
                note: note, isArchived: false, sortOrder: storedItems.count
            )
            storedItems.append(item)
            return item
        }

        func updateCatalogItem(id: UUID, title: String, emoji: String, costPoints: Int, note: String) {
            guard let index = storedItems.firstIndex(where: { $0.id == id }) else { return }
            let old = storedItems[index]
            storedItems[index] = RewardItem(
                id: id, title: title, emoji: emoji, costPoints: max(1, costPoints),
                note: note, isArchived: old.isArchived, sortOrder: old.sortOrder
            )
        }

        func deleteCatalogItem(id: UUID) { storedItems.removeAll { $0.id == id } }

        @discardableResult
        private func append(amount: Int, kind: RewardEntryKind, sourceGoalID: UUID?, note: String) -> RewardEntry {
            let entry = RewardEntry(
                id: UUID(), amount: amount, kind: kind, sourceGoalID: sourceGoalID,
                catalogItemID: nil, note: note, occurredAt: Date()
            )
            storedEntries.append(entry)
            return entry
        }
    }

    private func goal(complete: Bool = true, cadence: String = "월간") -> RewardClaimableGoal {
        RewardClaimableGoal(id: UUID(), title: "목표", emoji: "🎯", cadence: cadence, isComplete: complete)
    }

    private func make(points: Int = 0, items: [(String, Int)] = []) -> (RewardViewModel, FakeRepository) {
        let repository = FakeRepository()
        if points > 0 {
            repository.claim(
                goal(cadence: "주간"),
                policy: FixedWeeklyRewardPolicy(pointsPerGoal: points)
            )
        }
        for (title, cost) in items {
            repository.addCatalogItem(title: title, emoji: "🎁", costPoints: cost, note: "")
        }
        return (RewardViewModel(repository: repository), repository)
    }

    // MARK: - 파생 값

    func testBalanceAndProgressComeFromLedger() {
        let (viewModel, _) = make(points: 30, items: [("커피", 20), ("영화", 50)])
        viewModel.reload()

        XCTAssertEqual(viewModel.balance, 30)
        XCTAssertEqual(viewModel.progress.affordableCount, 1, "20P 짜리만 받을 수 있다")
        XCTAssertEqual(viewModel.progress.pointsToNext, 20, "50P 까지 20P 남았다")
    }

    /// 보관한 보상은 목록에서 감춘다.
    func testArchivedItemsAreHidden() {
        let repository = FakeRepository()
        repository.storedItems = [
            RewardItem(id: UUID(), title: "보임", emoji: "🎁", costPoints: 10, note: "", isArchived: false, sortOrder: 0),
            RewardItem(id: UUID(), title: "숨김", emoji: "🎁", costPoints: 10, note: "", isArchived: true, sortOrder: 1)
        ]
        let viewModel = RewardViewModel(repository: repository)
        viewModel.reload()

        XCTAssertEqual(viewModel.visibleItems.map(\.title), ["보임"])
    }

    // MARK: - 받기

    func testRedeemDeductsPointsAndUnboxes() throws {
        let (viewModel, _) = make(points: 50, items: [("커피", 20)])
        viewModel.unlockedMonthlyGoals = [goal()]
        viewModel.reload()
        let item = try XCTUnwrap(viewModel.visibleItems.first)

        viewModel.redeem(item)

        XCTAssertEqual(viewModel.balance, 30)
        XCTAssertEqual(viewModel.unboxed?.title, "커피")
        // 연출에 보여줄 잔액은 **깎인 뒤** 값이어야 한다.
        XCTAssertEqual(viewModel.unboxed?.remainingBalance, 30)
        XCTAssertEqual(viewModel.receivedRewards.count, 1)
    }

    /// 달성한 월간 목표가 없으면 포인트가 넉넉해도 받을 수 없다.
    func testRedeemWithoutUnlockedGoalFails() throws {
        let (viewModel, _) = make(points: 50, items: [("커피", 20)])
        viewModel.reload()
        let item = try XCTUnwrap(viewModel.visibleItems.first)

        viewModel.redeem(item)

        XCTAssertEqual(viewModel.balance, 50, "잔액이 그대로다")
        XCTAssertNil(viewModel.unboxed)
        XCTAssertFalse(viewModel.failureMessage.isEmpty)
    }

    func testRedeemWithInsufficientBalanceReportsShortfall() throws {
        let (viewModel, _) = make(points: 10, items: [("영화", 50)])
        viewModel.unlockedMonthlyGoals = [goal()]
        viewModel.reload()
        let item = try XCTUnwrap(viewModel.visibleItems.first)

        viewModel.redeem(item)

        XCTAssertTrue(viewModel.failureMessage.contains("40"), viewModel.failureMessage)
    }

    /// 한 목표로 두 번 받을 수 없다.
    func testSameGoalCannotBeRedeemedTwice() throws {
        let (viewModel, _) = make(points: 100, items: [("커피", 20)])
        let monthly = goal()
        viewModel.unlockedMonthlyGoals = [monthly]
        viewModel.reload()
        let item = try XCTUnwrap(viewModel.visibleItems.first)

        viewModel.redeem(item)
        XCTAssertTrue(viewModel.unlockedGoals.isEmpty, "쓴 목표는 후보에서 빠진다")

        viewModel.redeem(item)
        XCTAssertEqual(viewModel.balance, 80, "두 번째는 깎이지 않는다")
    }

    func testCanRedeemNeedsBothPointsAndUnlockedGoal() throws {
        let (viewModel, _) = make(points: 50, items: [("커피", 20)])
        viewModel.reload()
        let item = try XCTUnwrap(viewModel.visibleItems.first)

        XCTAssertFalse(viewModel.canRedeem(item), "목표가 없으면 못 받는다")
        XCTAssertTrue(viewModel.redeemHelpText(item).contains("월간 목표"))

        viewModel.unlockedMonthlyGoals = [goal()]
        XCTAssertTrue(viewModel.canRedeem(item))
    }

    // MARK: - 보상 목록

    func testAddAndUpdateAndDelete() throws {
        let (viewModel, _) = make()
        viewModel.reload()

        viewModel.addItem(title: "커피", emoji: "☕️", costPoints: 20, note: "")
        let added = try XCTUnwrap(viewModel.visibleItems.first)
        XCTAssertEqual(added.title, "커피")

        viewModel.updateItem(id: added.id, title: "라떼", emoji: "☕️", costPoints: 25, note: "")
        XCTAssertEqual(viewModel.visibleItems.first?.title, "라떼")
        XCTAssertEqual(viewModel.visibleItems.first?.costPoints, 25)

        viewModel.deleteItem(id: added.id)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }
}
