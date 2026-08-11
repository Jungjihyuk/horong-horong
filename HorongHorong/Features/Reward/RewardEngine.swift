import Foundation
import SwiftData

enum RewardRedeemError: Error, Equatable {
    /// 이 월간 목표로 이미 보상을 골랐다.
    case alreadyRedeemed
    /// 아직 달성하지 않은 목표.
    case goalNotComplete
    /// 잔액이 모자란다. 얼마나 모자라는지 담는다.
    case insufficientBalance(shortBy: Int)

    var message: String {
        switch self {
        case .alreadyRedeemed:
            return "이 목표의 보상은 이미 받았어요."
        case .goalNotComplete:
            return "아직 달성하지 않은 목표예요."
        case .insufficientBalance(let shortBy):
            return "\(shortBy)P가 더 필요해요."
        }
    }
}

enum RewardRevokeError: Error, Equatable {
    /// 이 목표로 받은 적이 없다.
    case notClaimed
    /// 이미 그 포인트로 보상을 받아 되돌릴 수 없다.
    case alreadySpent(shortBy: Int)

    var message: String {
        switch self {
        case .notClaimed:
            return "이 목표로 받은 포인트가 없어요."
        case .alreadySpent(let shortBy):
            return "이미 이 포인트로 보상을 받아서 되돌릴 수 없어요. (\(shortBy)P 모자람)"
        }
    }
}

/// 원장을 읽고 쓰는 자리. 계산은 전부 `RewardLedger`에 맡기고 여기서는 저장만 다룬다.
@MainActor
enum RewardEngine {
    // MARK: - 조회

    static func entries(in context: ModelContext) -> [RewardLedgerEntry] {
        let descriptor = FetchDescriptor<RewardLedgerEntry>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func catalogItems(in context: ModelContext) -> [RewardCatalogItem] {
        let descriptor = FetchDescriptor<RewardCatalogItem>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func balance(in context: ModelContext) -> Int {
        RewardLedger.balance(entries(in: context).map(\.snapshot))
    }

    static func hasClaimed(goalID: UUID, in context: ModelContext) -> Bool {
        RewardLedger.hasClaimed(goalID: goalID, in: entries(in: context).map(\.snapshot))
    }

    static func hasRedeemed(goalID: UUID, in context: ModelContext) -> Bool {
        RewardLedger.hasRedeemed(goalID: goalID, in: entries(in: context).map(\.snapshot))
    }

    // MARK: - 적립

    /// 주간 목표 달성 포인트를 적립한다.
    ///
    /// 미완료거나 이미 받은 목표면 아무것도 하지 않고 nil을 준다.
    /// 버튼이 안 보이는 상태에서도 호출될 수 있으므로 여기서 다시 막는다.
    @discardableResult
    static func claim(
        _ goal: RewardClaimableGoal,
        policy: RewardPointPolicy,
        in context: ModelContext
    ) -> RewardLedgerEntry? {
        guard goal.isComplete else { return nil }
        guard !hasClaimed(goalID: goal.id, in: context) else { return nil }

        let points = policy.points(forWeeklyGoal: goal)
        guard points > 0 else { return nil }

        let entry = RewardLedgerEntry(
            amount: points,
            kind: .earn,
            sourceGoalID: goal.id,
            note: "\(goal.emoji) \(goal.title)"
        )
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// 주간 목표 적립을 되돌린다.
    ///
    /// 할일을 잘못 체크해 목표가 잠깐 달성 상태가 됐을 때 쓴다.
    /// 이미 그 포인트로 보상을 받았으면 잔액이 음수가 되므로 거절한다.
    static func revokeClaim(
        goalID: UUID,
        in context: ModelContext
    ) -> Result<Int, RewardRevokeError> {
        let all = entries(in: context)
        guard let entry = all.first(where: { $0.kind == .earn && $0.sourceGoalID == goalID }) else {
            return .failure(.notClaimed)
        }

        let current = RewardLedger.balance(all.map(\.snapshot))
        guard current >= entry.amount else {
            return .failure(.alreadySpent(shortBy: entry.amount - current))
        }

        let revoked = entry.amount
        context.delete(entry)
        try? context.save()
        return .success(revoked)
    }

    // MARK: - 사용

    /// 월간 목표 달성 보상을 고른다. 잔액에서 항목 가격만큼 뺀다.
    static func redeem(
        item: RewardCatalogItem,
        forMonthlyGoal goal: RewardClaimableGoal,
        in context: ModelContext
    ) -> Result<RewardLedgerEntry, RewardRedeemError> {
        guard goal.isComplete else { return .failure(.goalNotComplete) }
        guard !hasRedeemed(goalID: goal.id, in: context) else { return .failure(.alreadyRedeemed) }

        let current = balance(in: context)
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
        try? context.save()
        return .success(entry)
    }

    // MARK: - 카탈로그

    @discardableResult
    static func addCatalogItem(
        title: String,
        emoji: String,
        costPoints: Int,
        note: String = "",
        in context: ModelContext
    ) -> RewardCatalogItem {
        let nextOrder = (catalogItems(in: context).map(\.sortOrder).max() ?? -1) + 1
        let item = RewardCatalogItem(
            title: title,
            emoji: emoji,
            costPoints: costPoints,
            note: note,
            sortOrder: nextOrder
        )
        context.insert(item)
        try? context.save()
        return item
    }

    /// 보상 항목을 지운다. 이미 쓴 이력은 `note` 스냅샷으로 남으므로 원장은 건드리지 않는다.
    static func deleteCatalogItem(_ item: RewardCatalogItem, in context: ModelContext) {
        context.delete(item)
        try? context.save()
    }
}
