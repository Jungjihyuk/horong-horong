import Foundation
import Observation

/// 팝오버 성취 요약의 상태.
///
/// **`@Query` 를 쓰지 않는다.** 목표는 성취 창에서 바뀌므로, 알림을 받아 다시 읽는다.
@MainActor
@Observable
final class AchievementSummaryViewModel {
    private(set) var goals: [AchievementGoal] = []

    private let repository: AchievementRepository
    private let settleOverdueGoals: SettleOverdueGoalsUseCase

    init(repository: AchievementRepository, rewardRepository: RewardRepository) {
        self.repository = repository
        self.settleOverdueGoals = SettleOverdueGoalsUseCase(
            achievementRepository: repository,
            rewardRepository: rewardRepository
        )
    }

    var currentWeekStart: Date { AchievementDataBuilder.weekStart(for: Date()) }

    /// 이번 주에 걸쳐 있는 주간 목표.
    var weeklyGoals: [AchievementGoal] {
        goals.filter { goal in
            goal.cadence == "주간"
                && AchievementDataBuilder.goal(goal, belongsToWeekStarting: currentWeekStart)
        }
    }

    func reload(basePoints: Int, penaltyRatio: Double, now: Date = Date()) {
        var details = repository.goals()
        goals = AchievementDataBuilder.goals(from: details, memos: repository.memos())

        // 달성 도장은 조립 결과를 보고 **명시적으로** 찍는다. 예전에는 조립 함수가
        // 그리는 도중에 저장소에 직접 썼다.
        let newlyCompleted = AchievementDataBuilder.newlyCompletedGoalIDs(goals: goals, details: details)
        if !newlyCompleted.isEmpty {
            repository.markCompleted(ids: newlyCompleted, at: now)
            // 방금 이룬 목표가 «유예 끝» 으로 잘못 잡히지 않게 다시 읽는다.
            details = repository.goals()
        }

        // 유예가 끝난 목표를 닫는 것도 조립이 끝난 뒤에 한다 — 같은 이유다.
        let settled = settleOverdueGoals(
            details: details,
            basePoints: basePoints,
            penaltyRatio: penaltyRatio,
            settlementEpoch: AchievementSettlementEpoch.resolve(now: now),
            now: now
        )
        guard !settled.isEmpty else { return }
        goals = AchievementDataBuilder.goals(from: repository.goals(), memos: repository.memos())
    }
}
