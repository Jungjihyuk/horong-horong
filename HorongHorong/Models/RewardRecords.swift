import Foundation
import SwiftData

/// 보상을 실제로 어떻게 지급하는가.
///
/// 지금은 사용자가 직접 수행하는 `manual` 하나뿐이다.
/// 향후 후보: 내 계좌 → 내 계좌 이체, 기프트카드, 외부 webhook.
/// 그때 필요한 것 — 이행 상태(대기/완료/실패) 필드, 비동기 핸들러, 자격증명 보관(Keychain).
/// 지금 필드 하나만 남겨두면 스키마 호환을 깨지 않고 나중에 붙일 수 있다.
enum RewardFulfillmentKind: String, Codable, CaseIterable {
    case manual

    var label: String {
        switch self {
        case .manual: return "직접 받기"
        }
    }
}

/// 포인트 적립·사용 원장. 잔액의 단일 출처다.
///
/// 잔액을 별도 필드로 캐시하지 않고 매번 합계를 낸다.
/// 건수가 주당 몇 개 수준이라 비용이 없고, 캐시는 원장과 어긋날 여지만 만든다.
@Model
final class RewardLedgerEntry {
    var id: UUID
    /// 적립은 양수, 사용은 음수.
    var amount: Int
    var kindRaw: String
    /// 적립이면 주간 목표, 사용이면 월간 목표의 id. 중복 적립·사용을 막는 키다.
    var sourceGoalID: UUID?
    /// 사용 시 고른 보상 항목.
    var catalogItemID: UUID?
    /// 목표·보상 제목 스냅샷. 원본이 지워져도 이력 문구가 남게 한다.
    var note: String
    var occurredAt: Date

    init(
        amount: Int,
        kind: RewardEntryKind,
        sourceGoalID: UUID? = nil,
        catalogItemID: UUID? = nil,
        note: String = "",
        occurredAt: Date = Date()
    ) {
        self.id = UUID()
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.sourceGoalID = sourceGoalID
        self.catalogItemID = catalogItemID
        self.note = note
        self.occurredAt = occurredAt
    }
}

extension RewardLedgerEntry {
    var kind: RewardEntryKind {
        RewardEntryKind(rawValue: kindRaw) ?? .earn
    }

    var snapshot: RewardEntrySnapshot {
        RewardEntrySnapshot(amount: amount, kind: kind, sourceGoalID: sourceGoalID)
    }
}

/// 내가 직접 정하는 보상 목록. 월간 목표를 달성했을 때 여기서 골라 쓴다.
@Model
final class RewardCatalogItem {
    var id: UUID
    var title: String
    var emoji: String
    var costPoints: Int
    var note: String
    var sortOrder: Int
    /// 목록에서 감추되 지난 이력은 유지하고 싶을 때.
    var isArchived: Bool
    var fulfillmentKindRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String,
        emoji: String = "🎁",
        costPoints: Int = 10,
        note: String = "",
        sortOrder: Int = 0,
        isArchived: Bool = false,
        fulfillmentKind: RewardFulfillmentKind = .manual
    ) {
        self.id = UUID()
        self.title = title
        self.emoji = emoji
        self.costPoints = max(1, costPoints)
        self.note = note
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.fulfillmentKindRaw = fulfillmentKind.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension RewardCatalogItem {
    var fulfillmentKind: RewardFulfillmentKind {
        RewardFulfillmentKind(rawValue: fulfillmentKindRaw) ?? .manual
    }

    var snapshot: RewardItemSnapshot {
        RewardItemSnapshot(id: id, costPoints: costPoints, isArchived: isArchived)
    }
}
