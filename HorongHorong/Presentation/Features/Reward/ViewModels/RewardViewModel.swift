import Foundation
import Observation

/// 보상 탭의 상태.
///
/// **`@Query` 를 쓰지 않는다.** 원장은 이 화면과 성취 화면 두 곳에서 바뀌므로, 쓰기 뒤
/// 재적재만으로는 부족하다 — 성취 쪽 적립이 반영되도록 화면이 나타날 때도 다시 읽는다.
@MainActor
@Observable
final class RewardViewModel {
    private(set) var entries: [RewardEntry] = []
    private(set) var items: [RewardItem] = []
    private(set) var failureMessage = ""
    /// 개봉 연출에 넘길 결과. 원장은 이미 기록된 뒤다.
    private(set) var unboxed: UnboxedReward?

    /// 성취 화면이 넘겨준 «달성했지만 아직 보상을 안 고른» 월간 목표.
    var unlockedMonthlyGoals: [RewardClaimableGoal] = [] {
        didSet { guard unlockedMonthlyGoals != oldValue else { return } }
    }

    private let repository: RewardRepository

    init(repository: RewardRepository) {
        self.repository = repository
    }

    struct UnboxedReward: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let title: String
        let costPoints: Int
        let remainingBalance: Int
    }

    // MARK: - 파생 값

    /// 한 번의 렌더에서 여러 번 쓰이므로 재적재 때 한 번만 계산한다.
    private(set) var balance = 0
    private(set) var progress = RewardProgress(
        balance: 0, affordableCount: 0, pointsToNext: nil, fillRatio: 0, marks: []
    )

    /// 보관하지 않은 보상만 목록에 보인다.
    var visibleItems: [RewardItem] { items.filter { !$0.isArchived } }

    /// 아직 보상을 고르지 않은 달성 목표.
    var unlockedGoals: [RewardClaimableGoal] {
        let snapshots = entries.map(\.snapshot)
        return unlockedMonthlyGoals.filter { !RewardLedger.hasRedeemed(goalID: $0.id, in: snapshots) }
    }

    /// 지금까지 받은 보상. 전리품 선반에 늘어놓는다.
    var receivedRewards: [RewardEntry] { entries.filter { $0.kind == .spend } }

    func canRedeem(_ item: RewardItem) -> Bool {
        balance >= item.costPoints && !unlockedGoals.isEmpty
    }

    func redeemHelpText(_ item: RewardItem) -> String {
        if balance < item.costPoints {
            return "\(item.costPoints - balance)P 가 더 필요해요"
        }
        if unlockedGoals.isEmpty {
            return "월간 목표를 달성하면 받을 수 있어요"
        }
        return "달성한 월간 목표를 걸고 이 보상을 받습니다"
    }

    // MARK: - 읽기

    /// 저장소가 바뀌었다고 알릴 때도 부른다 — 성취 화면에서 적립하면 여기가 알아야 한다.
    func reload() {
        entries = repository.entries()
        items = repository.catalogItems()
        balance = RewardLedger.balance(entries.map(\.snapshot))
        progress = RewardLedger.progress(balance: balance, items: items.map(\.snapshot))
    }

    // MARK: - 쓰기

    /// 달성한 월간 목표 하나를 걸고 보상을 받는다. 원장에 사용 기록이 남고 포인트가 깎인다.
    func redeem(_ item: RewardItem) {
        guard let unlocked = unlockedGoals.first else {
            failureMessage = "월간 목표를 달성해야 보상을 받을 수 있어요."
            return
        }

        switch repository.redeem(itemID: item.id, forMonthlyGoal: unlocked) {
        case .success:
            failureMessage = ""
            reload()
            unboxed = UnboxedReward(
                emoji: item.emoji,
                title: item.title,
                costPoints: item.costPoints,
                // 재적재가 끝난 뒤라 잔액은 이미 깎인 값이다.
                remainingBalance: balance
            )
        case .failure(let error):
            failureMessage = error.message
        }
    }

    func dismissUnboxing() {
        unboxed = nil
    }

    func addItem(title: String, emoji: String, costPoints: Int, note: String) {
        repository.addCatalogItem(title: title, emoji: emoji, costPoints: costPoints, note: note)
        reload()
    }

    func updateItem(id: UUID, title: String, emoji: String, costPoints: Int, note: String) {
        repository.updateCatalogItem(id: id, title: title, emoji: emoji, costPoints: costPoints, note: note)
        reload()
    }

    func deleteItem(id: UUID) {
        repository.deleteCatalogItem(id: id)
        reload()
    }
}
