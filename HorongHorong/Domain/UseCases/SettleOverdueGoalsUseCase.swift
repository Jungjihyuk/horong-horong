import Foundation

/// 유예가 끝난 목표를 실패로 닫고 포인트를 깎는다.
///
/// 목표 저장소와 보상 저장소 **둘을 함께** 움직여야 해서 UseCase 로 뺐다. 화면이 두 저장소를
/// 순서대로 부르게 두면 그 순서가 화면마다 달라지고, 한쪽만 성공한 상태가 생긴다.
///
/// **여러 번 불러도 결과가 같다.** 성취 창과 팝오버 요약이 같은 알림으로 함께 깨어나므로
/// 같은 틱에 두 번 도는 일이 실제로 일어난다. 세 겹으로 막는다:
/// 1. 정책이 이미 닫혔거나 이미 이룬 목표를 애초에 고르지 않는다
/// 2. `markFailed` 가 `closedAt == nil` 인 것만 찍는다
/// 3. 원장이 `hasPenalized` 로 같은 목표의 두 번째 차감을 거절한다
@MainActor
struct SettleOverdueGoalsUseCase {
    private let achievementRepository: AchievementRepository
    private let rewardRepository: RewardRepository

    init(achievementRepository: AchievementRepository, rewardRepository: RewardRepository) {
        self.achievementRepository = achievementRepository
        self.rewardRepository = rewardRepository
    }

    /// 이번에 닫은 목표들. 화면은 이 값으로 「되돌리기」 안내를 띄운다.
    @discardableResult
    func callAsFunction(
        details: [AchievementGoalDetail],
        basePoints: Int,
        penaltyRatio: Double,
        settlementEpoch: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> [AchievementGoalDetail] {
        let expired = details.filter { detail in
            guard case let .expired(deadline) = AchievementSettlementPolicy.state(
                cadence: detail.cadence,
                dueDate: detail.dueDate,
                createdAt: detail.createdAt,
                completedAt: detail.completedAt,
                closedAt: detail.closedAt,
                now: now,
                calendar: calendar
            ) else {
                return false
            }
            // 기능을 켜기 전에 마감된 목표는 자동으로 닫지 않는다. 고를 기회를 준 적이 없는데
            // 벌부터 주게 된다 — 배너에는 올라오니 사용자가 직접 정리하면 그때 정산한다.
            return deadline >= settlementEpoch
        }
        guard !expired.isEmpty else { return [] }

        achievementRepository.markFailed(ids: expired.map(\.id), at: now, reason: .expired)

        for detail in expired {
            let points = AchievementSettlementPolicy.penaltyPoints(
                cadence: detail.cadence,
                basePoints: basePoints,
                ratio: penaltyRatio
            )
            guard points > 0 else { continue }
            rewardRepository.penalize(
                goalID: detail.id,
                nominalPoints: points,
                note: "\(detail.emoji) \(detail.title)",
                at: now
            )
        }
        return expired
    }
}
