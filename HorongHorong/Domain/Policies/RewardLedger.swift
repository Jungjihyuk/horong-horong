import Foundation

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

    /// 이 목표로 이미 패널티를 받았는지.
    ///
    /// `hasClaimed` 와 같은 이유로 필요하다 — 성취 창과 팝오버가 같은 틱에 정산할 수 있고,
    /// 목표를 다시 열었다 닫으면 또 깎일 수 있다. **목표 하나당 차감도 평생 한 번이다.**
    static func hasPenalized(goalID: UUID, in entries: [RewardEntrySnapshot]) -> Bool {
        entries.contains { $0.kind == .penalty && $0.sourceGoalID == goalID }
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
        let active = items
            .filter { !$0.isArchived }
            .sorted { $0.costPoints < $1.costPoints }

        // 게이지의 100% 는 **가장 비싼 보상**이다.
        // 가장 싼 미달 보상을 기준으로 삼으면 하나 살 수 있게 되는 순간 계속 가득 차 있게 되고,
        // 전체 합계를 기준으로 삼으면 보상을 추가할 때마다 게이지가 뚝 떨어져 등록을 벌주게 된다.
        let ceiling = active.map(\.costPoints).max() ?? 0

        let marks = active.map { item in
            RewardMark(
                id: item.id,
                emoji: item.emoji,
                title: item.title,
                costPoints: item.costPoints,
                heightRatio: ceiling > 0 ? Double(item.costPoints) / Double(ceiling) : 0,
                isReached: item.costPoints <= balance
            )
        }

        return RewardProgress(
            balance: balance,
            affordableCount: active.filter { $0.costPoints <= balance }.count,
            pointsToNext: active.first { $0.costPoints > balance }.map { $0.costPoints - balance },
            fillRatio: fillRatio(balance: balance, target: ceiling),
            marks: marks
        )
    }
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
