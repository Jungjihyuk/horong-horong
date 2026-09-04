import Foundation
import SwiftData

/// `RewardRepository` 의 SwiftData 구현.
///
/// 예전 `RewardEngine`(정적 메서드 + `ModelContext` 인자)을 옮긴 것이다. 계산은 여전히
/// `RewardLedger` 에 맡기고 여기서는 저장만 다룬다.
@MainActor
final class SwiftDataRewardRepository: RewardRepository {
    /// 원장이 바뀌었다. **보상 탭과 성취 화면 두 곳에서 쓰기가 일어나므로**, 쓴 쪽이
    /// 재적재하는 것만으로는 다른 쪽이 옛 값을 보게 된다. `@Query` 의 자동 갱신을
    /// 이 알림 하나로 대신한다(파일럿에서 정한 «바깥 변경까지 받아야 할 때만 알림»).
    static let didChangeNotification = Notification.Name("RewardLedgerDidChange")

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - 조회

    func entries() -> [RewardEntry] {
        records().map(Self.toEntry)
    }

    func catalogItems() -> [RewardItem] {
        let descriptor = FetchDescriptor<RewardCatalogItem>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(Self.toItem)
    }

    func balance() -> Int {
        RewardLedger.balance(records().map(\.snapshot))
    }

    func hasClaimed(goalID: UUID) -> Bool {
        RewardLedger.hasClaimed(goalID: goalID, in: records().map(\.snapshot))
    }

    func hasRedeemed(goalID: UUID) -> Bool {
        RewardLedger.hasRedeemed(goalID: goalID, in: records().map(\.snapshot))
    }

    // MARK: - 적립

    @discardableResult
    func claim(_ goal: RewardClaimableGoal, policy: RewardPointPolicy) -> Int? {
        guard goal.isComplete else { return nil }
        guard !hasClaimed(goalID: goal.id) else { return nil }

        let points = policy.points(forWeeklyGoal: goal)
        guard points > 0 else { return nil }

        let entry = RewardLedgerEntry(
            amount: points,
            kind: .earn,
            sourceGoalID: goal.id,
            note: "\(goal.emoji) \(goal.title)"
        )
        context.insert(entry)
        save()
        return points
    }

    func revokeClaim(goalID: UUID) -> Result<Int, RewardRevokeError> {
        let all = records()
        guard let entry = all.first(where: { $0.kind == .earn && $0.sourceGoalID == goalID }) else {
            return .failure(.notClaimed)
        }

        // 이미 그 포인트로 보상을 받았으면 되돌릴 때 잔액이 음수가 된다.
        let current = RewardLedger.balance(all.map(\.snapshot))
        guard current >= entry.amount else {
            return .failure(.alreadySpent(shortBy: entry.amount - current))
        }

        let revoked = entry.amount
        context.delete(entry)
        save()
        return .success(revoked)
    }

    // MARK: - 패널티

    func hasPenalized(goalID: UUID) -> Bool {
        RewardLedger.hasPenalized(goalID: goalID, in: records().map(\.snapshot))
    }

    @discardableResult
    func penalize(
        goalID: UUID,
        nominalPoints: Int,
        note: String,
        at date: Date
    ) -> RewardPenaltyResult? {
        guard nominalPoints > 0 else { return nil }
        let all = records()
        let snapshots = all.map(\.snapshot)
        guard !RewardLedger.hasPenalized(goalID: goalID, in: snapshots) else { return nil }
        // 이 목표로 이미 포인트를 받았으면 깎지 않는다. 주고 또 뺏으면 이중 장부가 된다.
        guard !RewardLedger.hasClaimed(goalID: goalID, in: snapshots) else { return nil }

        // **잔액은 0 에서 바닥.** 빚을 지고 시작하면 회복이 멀어져 다시 목표를 잡을 맛이 없다.
        let charged = min(nominalPoints, max(0, RewardLedger.balance(snapshots)))
        guard charged > 0 else { return nil }

        let forgiven = nominalPoints - charged
        // 왜 5P 가 아니라 3P 만 깎였는지 나중에 설명할 수 있어야 한다. `note` 는 원본이
        // 지워져도 남는 이력 문구라 그 사정을 여기에 적는다.
        let suffix = forgiven > 0 ? " · 명목 \(nominalPoints)P 중 \(charged)P" : ""
        let entry = RewardLedgerEntry(
            amount: -charged,
            kind: .penalty,
            sourceGoalID: goalID,
            note: note + suffix
        )
        entry.occurredAt = date
        context.insert(entry)
        save()
        return RewardPenaltyResult(nominal: nominalPoints, charged: charged, forgiven: forgiven)
    }

    func revokePenalty(goalID: UUID) -> Int? {
        guard let entry = records().first(where: { $0.kind == .penalty && $0.sourceGoalID == goalID }) else {
            return nil
        }
        // `revokeClaim` 과 달리 잔액을 **늘리는** 방향이라 «이미 써 버렸다» 를 따질 필요가 없다.
        let restored = -entry.amount
        context.delete(entry)
        save()
        return restored
    }

    // MARK: - 사용

    func redeem(itemID: UUID, forMonthlyGoal goal: RewardClaimableGoal) -> Result<RewardEntry, RewardRedeemError> {
        guard goal.isComplete else { return .failure(.goalNotComplete) }
        guard !hasRedeemed(goalID: goal.id) else { return .failure(.alreadyRedeemed) }
        guard let item = findItem(itemID) else { return .failure(.goalNotComplete) }

        let current = balance()
        guard current >= item.costPoints else {
            return .failure(.insufficientBalance(shortBy: item.costPoints - current))
        }

        let entry = RewardLedgerEntry(
            amount: -item.costPoints,
            kind: .spend,
            sourceGoalID: goal.id,
            catalogItemID: item.id,
            note: "\(item.emoji) \(item.title)"
        )
        context.insert(entry)
        save()
        return .success(Self.toEntry(entry))
    }

    // MARK: - 카탈로그

    @discardableResult
    func addCatalogItem(title: String, emoji: String, costPoints: Int, note: String) -> RewardItem {
        let nextOrder = (catalogItems().map(\.sortOrder).max() ?? -1) + 1
        let item = RewardCatalogItem(
            title: title,
            emoji: emoji,
            costPoints: costPoints,
            note: note,
            sortOrder: nextOrder
        )
        context.insert(item)
        save()
        return Self.toItem(item)
    }

    func updateCatalogItem(id: UUID, title: String, emoji: String, costPoints: Int, note: String) {
        guard let item = findItem(id) else { return }
        item.title = title
        item.emoji = emoji
        item.costPoints = max(1, costPoints)
        item.note = note
        item.updatedAt = Date()
        save()
    }

    func deleteCatalogItem(id: UUID) {
        guard let item = findItem(id) else { return }
        context.delete(item)
        save()
    }

    // MARK: - 내부

    private func save() {
        try? context.save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func records() -> [RewardLedgerEntry] {
        let descriptor = FetchDescriptor<RewardLedgerEntry>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func findItem(_ id: UUID) -> RewardCatalogItem? {
        var descriptor = FetchDescriptor<RewardCatalogItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func toEntry(_ record: RewardLedgerEntry) -> RewardEntry {
        RewardEntry(
            id: record.id,
            amount: record.amount,
            kind: record.kind,
            sourceGoalID: record.sourceGoalID,
            catalogItemID: record.catalogItemID,
            note: record.note,
            occurredAt: record.occurredAt
        )
    }

    private static func toItem(_ record: RewardCatalogItem) -> RewardItem {
        RewardItem(
            id: record.id,
            title: record.title,
            emoji: record.emoji,
            costPoints: record.costPoints,
            note: record.note,
            isArchived: record.isArchived,
            sortOrder: record.sortOrder
        )
    }
}
