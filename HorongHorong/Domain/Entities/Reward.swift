import Foundation

// 포인트·보상의 값 타입들.
//
// **저장은 `RewardLedgerEntry`·`RewardCatalogItem`(`@Model`)이 하고 그건 Data 계층에 남는다.**
// 화면과 계산은 여기 있는 타입만 본다.

enum RewardEntryKind: String, Codable {
    case earn
    case spend
    /// 마감을 넘겨 실패로 마감한 목표의 차감. `spend` 와 부호는 같지만 «내가 쓴 것» 이 아니다.
    ///
    /// 이력 화면의 «받은 것 / 쓴 것» 합계를 갈라 놓으려고 종류를 나눈다 —
    /// `spend` 로 뭉뚱그리면 보상을 산 적 없는데 «쓴 것» 이 쌓인다.
    case penalty
}

/// 원장 한 줄의 계산용 스냅샷. SwiftData 없이 계산·테스트하기 위한 값 타입이다.
struct RewardEntrySnapshot: Equatable {
    let amount: Int
    let kind: RewardEntryKind
    let sourceGoalID: UUID?

    init(amount: Int, kind: RewardEntryKind, sourceGoalID: UUID? = nil) {
        self.amount = amount
        self.kind = kind
        self.sourceGoalID = sourceGoalID
    }
}

/// 패널티를 매긴 결과. 명목과 실제가 다를 수 있어 셋을 함께 돌려준다.
struct RewardPenaltyResult: Equatable, Sendable {
    /// 정책이 정한 차감액.
    let nominal: Int
    /// 실제로 깎인 양. 잔액이 모자라면 명목보다 작다.
    let charged: Int
    /// 잔액이 모자라 못 깎은 양.
    let forgiven: Int
}

/// 보상 항목의 계산용 스냅샷.
struct RewardItemSnapshot: Equatable {
    let id: UUID
    let emoji: String
    let title: String
    let costPoints: Int
    let isArchived: Bool

    init(
        id: UUID = UUID(),
        emoji: String = "🎁",
        title: String = "",
        costPoints: Int,
        isArchived: Bool = false
    ) {
        self.id = id
        self.emoji = emoji
        self.title = title
        self.costPoints = costPoints
        self.isArchived = isArchived
    }
}

/// 등잔에 그을 눈금 하나. 보상 하나가 눈금 하나다.
struct RewardMark: Equatable, Identifiable {
    let id: UUID
    let emoji: String
    let title: String
    let costPoints: Int
    /// 등잔 바닥에서의 높이 0…1.
    let heightRatio: Double
    /// 기름이 이 눈금을 넘었는가 — 지금 받을 수 있는가.
    let isReached: Bool
}

/// 목표를 Reward 쪽으로 넘기기 위한 경계 타입.
/// `AchievementGoal`은 `AchievementViews.swift`의 file-private 타입이라 직접 쓸 수 없다.
struct RewardClaimableGoal: Equatable {
    let id: UUID
    let title: String
    let emoji: String
    let cadence: String
    let isComplete: Bool

    var isWeekly: Bool { cadence == "주간" }
    var isMonthly: Bool { cadence == "월간" }
}

/// 호롱불과 안내 문구가 함께 쓰는 진행 상태.
struct RewardProgress: Equatable {
    let balance: Int
    /// 지금 잔액으로 받을 수 있는 보상 개수.
    let affordableCount: Int
    /// 가장 싼 미달 보상까지 남은 포인트. 전부 받을 수 있으면 nil.
    let pointsToNext: Int?
    let fillRatio: Double
    /// 등잔에 그을 눈금. 싼 것부터.
    let marks: [RewardMark]

    var hasAffordableReward: Bool { affordableCount > 0 }
}

/// 원장 한 줄 전체. 이력 창과 전리품 선반이 쓴다.
///
/// `RewardEntrySnapshot` 과 나눈 이유: 계산에는 금액·종류·목표 id 만 있으면 되고,
/// 그 셋만 받으면 **잔액 계산이 화면 사정(제목·시각)에 딸려 가지 않는다.**
struct RewardEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let amount: Int
    let kind: RewardEntryKind
    let sourceGoalID: UUID?
    let catalogItemID: UUID?
    /// 목표·보상 제목 스냅샷. 원본이 지워져도 이력 문구가 남는다.
    let note: String
    let occurredAt: Date

    var snapshot: RewardEntrySnapshot {
        RewardEntrySnapshot(amount: amount, kind: kind, sourceGoalID: sourceGoalID)
    }
}

/// 보상 목록의 한 줄 전체. 편집 화면이 메모까지 필요로 한다.
struct RewardItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let emoji: String
    let costPoints: Int
    let note: String
    let isArchived: Bool
    let sortOrder: Int

    var snapshot: RewardItemSnapshot {
        RewardItemSnapshot(
            id: id,
            emoji: emoji,
            title: title,
            costPoints: costPoints,
            isArchived: isArchived
        )
    }
}
