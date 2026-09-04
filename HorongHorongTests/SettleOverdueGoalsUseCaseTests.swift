import SwiftData
import XCTest
@testable import 호롱호롱

/// 유예가 끝난 목표를 자동으로 닫고 포인트를 깎는 흐름.
///
/// 성취 창과 팝오버 요약이 같은 알림으로 함께 깨어나므로 **같은 틱에 두 번 도는 일이
/// 실제로 일어난다.** 멱등성이 이 파일의 첫 번째 관심사다.
@MainActor
final class SettleOverdueGoalsUseCaseTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func draft(_ title: String, cadence: String = "주간", dueDate: Date? = nil) -> AchievementGoalDraft {
        AchievementGoalDraft(
            title: title,
            emoji: "🎯",
            cadence: cadence,
            rule: "",
            targetCount: 1,
            targetValueText: nil,
            periodText: nil,
            dueDate: dueDate,
            colorHex: "#E87333",
            roleName: "나",
            vision: "",
            yearGoal: nil,
            monthGoal: nil,
            linkedMemoIDs: [],
            sourceRunID: nil,
            sourceSuggestionID: nil
        )
    }

    /// 저장소가 `createdAt` 을 스스로 `Date()` 로 찍으므로 «며칠 뒤» 같은 고정 오프셋을 쓰면
    /// **오늘이 무슨 요일이냐에 따라 결과가 달라진다.** 실제 마감·유예 경계에서 시각을 뽑는다.
    private func deadline(of goal: AchievementGoalDetail) throws -> Date {
        try XCTUnwrap(
            AchievementSettlementPolicy.effectiveDeadline(
                cadence: goal.cadence,
                dueDate: goal.dueDate,
                createdAt: goal.createdAt
            )
        )
    }

    /// 유예가 끝난 직후 — 자동 마감 대상이 되는 첫 순간.
    private func afterGracePeriod(of goal: AchievementGoalDetail) throws -> Date {
        AchievementSettlementPolicy.graceEnd(
            after: try deadline(of: goal),
            cadence: goal.cadence
        )
    }

    /// 마감은 지났지만 유예는 남은 시점.
    private func insideGracePeriod(of goal: AchievementGoalDetail) throws -> Date {
        try deadline(of: goal).addingTimeInterval(60)
    }

    private func fund(_ reward: SwiftDataRewardRepository, points: Int) {
        reward.claim(
            RewardClaimableGoal(id: UUID(), title: "이룬 목표", emoji: "🎯", cadence: "주간", isComplete: true),
            policy: FixedWeeklyRewardPolicy(pointsPerGoal: points)
        )
    }

    func testExpiredGoalIsClosedAndPenalizedOnce() throws {
        let container = try makeContainer()
        let achievement = SwiftDataAchievementRepository(context: container.mainContext)
        let reward = SwiftDataRewardRepository(context: container.mainContext)
        fund(reward, points: 40)
        let goal = try achievement.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        let now = try afterGracePeriod(of: goal)
        let settle = SettleOverdueGoalsUseCase(achievementRepository: achievement, rewardRepository: reward)

        let first = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0.5,
            settlementEpoch: goal.createdAt,
            now: now
        )
        let second = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0.5,
            settlementEpoch: goal.createdAt,
            now: now
        )

        XCTAssertEqual(first.map(\.id), [goal.id])
        XCTAssertTrue(second.isEmpty, "두 번째 정산은 아무것도 닫지 않아야 한다")
        XCTAssertEqual(achievement.goals().first { $0.id == goal.id }?.closedReason, .expired)
        XCTAssertEqual(reward.balance(), 30, "40P 에서 10P 만 깎여야 한다")
    }

    /// 아직 유예 중인 목표는 사용자가 고를 몫이다. 자동으로 닫으면 선택권이 사라진다.
    func testGoalStillInGracePeriodIsLeftAlone() throws {
        let container = try makeContainer()
        let achievement = SwiftDataAchievementRepository(context: container.mainContext)
        let reward = SwiftDataRewardRepository(context: container.mainContext)
        fund(reward, points: 40)
        let goal = try achievement.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        let settle = SettleOverdueGoalsUseCase(achievementRepository: achievement, rewardRepository: reward)

        let settled = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0.5,
            settlementEpoch: goal.createdAt,
            // 마감은 지났지만 유예는 남았다
            now: try insideGracePeriod(of: goal)
        )

        XCTAssertTrue(settled.isEmpty)
        XCTAssertEqual(reward.balance(), 40)
    }

    /// **기능을 켜기 전에 마감된 목표는 자동으로 닫지 않는다.**
    /// 고를 기회를 준 적이 없는데 벌부터 주면 첫인상이 벌칙만 남는다.
    func testGoalThatExpiredBeforeTheEpochIsNotSettledAutomatically() throws {
        let container = try makeContainer()
        let achievement = SwiftDataAchievementRepository(context: container.mainContext)
        let reward = SwiftDataRewardRepository(context: container.mainContext)
        fund(reward, points: 40)
        let goal = try achievement.createGoal(draft("옛날 목표"), childGoalIDs: [], newChildTitles: [])
        let now = try afterGracePeriod(of: goal)
        let settle = SettleOverdueGoalsUseCase(achievementRepository: achievement, rewardRepository: reward)

        let settled = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0.5,
            // 시작선을 «지금» 으로 두면 이 목표의 마감은 그보다 앞선다
            settlementEpoch: now,
            now: now
        )

        XCTAssertTrue(settled.isEmpty)
        XCTAssertNil(achievement.goals().first { $0.id == goal.id }?.closedAt)
        XCTAssertEqual(reward.balance(), 40)
    }

    /// 월간 목표는 보상 교환 자격을 잃는 것으로 갈음한다 — 하위 주간이 이미 깎였다.
    func testMonthlyGoalIsClosedWithoutPointPenalty() throws {
        let container = try makeContainer()
        let achievement = SwiftDataAchievementRepository(context: container.mainContext)
        let reward = SwiftDataRewardRepository(context: container.mainContext)
        fund(reward, points: 40)
        let goal = try achievement.createGoal(
            draft("9월 목표", cadence: "월간"),
            childGoalIDs: [],
            newChildTitles: []
        )
        let settle = SettleOverdueGoalsUseCase(achievementRepository: achievement, rewardRepository: reward)

        let settled = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0.5,
            settlementEpoch: goal.createdAt,
            now: try afterGracePeriod(of: goal)
        )

        XCTAssertEqual(settled.map(\.id), [goal.id])
        XCTAssertEqual(reward.balance(), 40, "월간 실패는 포인트를 깎지 않는다")
        XCTAssertFalse(reward.hasPenalized(goalID: goal.id))
    }

    /// 이미 이룬 목표는 마감이 지나도 실패가 아니다.
    func testCompletedGoalIsNeverSettled() throws {
        let container = try makeContainer()
        let achievement = SwiftDataAchievementRepository(context: container.mainContext)
        let reward = SwiftDataRewardRepository(context: container.mainContext)
        fund(reward, points: 40)
        let goal = try achievement.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        achievement.markCompleted(ids: [goal.id], at: goal.createdAt)
        let settle = SettleOverdueGoalsUseCase(achievementRepository: achievement, rewardRepository: reward)

        let settled = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0.5,
            settlementEpoch: goal.createdAt,
            now: try afterGracePeriod(of: goal)
        )

        XCTAssertTrue(settled.isEmpty)
        XCTAssertEqual(reward.balance(), 40)
    }

    /// 패널티 비율이 0이면 닫기만 하고 깎지 않는다 — 패널티를 끈 상태다.
    func testZeroRatioClosesWithoutCharging() throws {
        let container = try makeContainer()
        let achievement = SwiftDataAchievementRepository(context: container.mainContext)
        let reward = SwiftDataRewardRepository(context: container.mainContext)
        fund(reward, points: 40)
        let goal = try achievement.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        let settle = SettleOverdueGoalsUseCase(achievementRepository: achievement, rewardRepository: reward)

        let settled = settle(
            details: achievement.goals(),
            basePoints: 20,
            penaltyRatio: 0,
            settlementEpoch: goal.createdAt,
            now: try afterGracePeriod(of: goal)
        )

        XCTAssertEqual(settled.map(\.id), [goal.id])
        XCTAssertEqual(reward.balance(), 40)
    }
}
