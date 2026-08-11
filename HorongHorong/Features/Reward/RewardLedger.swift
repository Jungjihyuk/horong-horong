import Foundation

enum RewardEntryKind: String, Codable {
    case earn
    case spend
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

/// 보상 항목의 계산용 스냅샷.
struct RewardItemSnapshot: Equatable {
    let id: UUID
    let costPoints: Int
    let isArchived: Bool

    init(id: UUID = UUID(), costPoints: Int, isArchived: Bool = false) {
        self.id = id
        self.costPoints = costPoints
        self.isArchived = isArchived
    }
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

/// 포인트 계산. 전부 순수 함수라 SwiftData 없이 테스트한다.
enum RewardLedger {
    /// 현재 잔액. 적립(양수)과 사용(음수)을 그대로 더한다.
    static func balance(_ entries: [RewardEntrySnapshot]) -> Int {
        entries.reduce(0) { $0 + $1.amount }
    }

    /// 이 주간 목표로 이미 포인트를 받았는지.
    ///
    /// 목표 달성 여부가 파생값(`done >= total`)이라 할 일을 뺐다 다시 붙이면 완료 상태가 오간다.
    /// 목표 하나당 적립은 평생 한 번으로 못박아 재적립을 막는다.
    static func hasClaimed(goalID: UUID, in entries: [RewardEntrySnapshot]) -> Bool {
        entries.contains { $0.kind == .earn && $0.sourceGoalID == goalID }
    }

    /// 이 월간 목표로 이미 보상을 골랐는지.
    static func hasRedeemed(goalID: UUID, in entries: [RewardEntrySnapshot]) -> Bool {
        entries.contains { $0.kind == .spend && $0.sourceGoalID == goalID }
    }

    /// 호롱불에 채울 기름 높이 0…1.
    /// `target`은 다음 보상의 가격이다. 0 이하면 채울 기준이 없으므로 0을 준다.
    static func fillRatio(balance: Int, target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(balance) / Double(target)))
    }

    /// 화면이 필요로 하는 진행 상태를 한 번에 계산한다.
    ///
    /// **살 수 있는 보상이 하나라도 있으면 그것부터 알린다.**
    /// 미달 보상만 보고 "다음 보상까지 N P"를 띄우면, 이미 받을 수 있는 보상이 있는데도
    /// 아직 멀었다고 말하게 된다.
    static func progress(balance: Int, items: [RewardItemSnapshot]) -> RewardProgress {
        let active = items.filter { !$0.isArchived }
        let affordableCount = active.filter { $0.costPoints <= balance }.count

        if affordableCount > 0 {
            return RewardProgress(
                balance: balance,
                affordableCount: affordableCount,
                pointsToNext: nil,
                fillRatio: 1
            )
        }

        guard let cheapest = active.map(\.costPoints).min() else {
            // 보상 목록이 비면 채울 기준 자체가 없다.
            return RewardProgress(balance: balance, affordableCount: 0, pointsToNext: nil, fillRatio: 0)
        }

        return RewardProgress(
            balance: balance,
            affordableCount: 0,
            pointsToNext: cheapest - balance,
            fillRatio: fillRatio(balance: balance, target: cheapest)
        )
    }
}

/// 호롱불과 안내 문구가 함께 쓰는 진행 상태.
struct RewardProgress: Equatable {
    let balance: Int
    /// 지금 잔액으로 받을 수 있는 보상 개수.
    let affordableCount: Int
    /// 가장 싼 보상까지 남은 포인트. 이미 받을 수 있는 게 있으면 nil.
    let pointsToNext: Int?
    let fillRatio: Double

    var hasAffordableReward: Bool { affordableCount > 0 }
}

/// 적립 규칙. 정책을 바꿔 끼울 수 있는 지점이며, 이 모듈의 유일한 추상화다.
protocol RewardPointPolicy {
    func points(forWeeklyGoal goal: RewardClaimableGoal) -> Int
}

/// 주간 목표 하나당 같은 포인트를 주는 기본 정책.
struct FixedWeeklyRewardPolicy: RewardPointPolicy {
    let pointsPerGoal: Int

    func points(forWeeklyGoal goal: RewardClaimableGoal) -> Int {
        guard goal.isWeekly, goal.isComplete else { return 0 }
        return max(0, pointsPerGoal)
    }
}
