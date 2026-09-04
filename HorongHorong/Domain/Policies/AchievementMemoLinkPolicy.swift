import Foundation

/// 할일을 묶을 수 있는 목표. 저장된 값(`AchievementGoalDetail`)과 화면이 볼 모습
/// (`AchievementGoal`) 둘 다 이 모습으로 정책에 들어온다 — 정책이 어느 계층의
/// 타입인지 몰라도 되게.
protocol AchievementLinkableGoal {
    var id: UUID { get }
    var title: String { get }
    var cadence: String { get }
    var createdAt: Date { get }
    var linkedMemoIDs: [UUID] { get }
}

/// 할일과 주간 목표를 잇는 규칙.
///
/// **한 할일은 주간 목표 하나에만 묶인다.** 두 목표가 같은 할일을 나눠 가지면 할일 하나를
/// 끝내는 것으로 두 목표가 함께 달성되고, 성취 타임라인에도 같은 카드가 두 번 선다.
///
/// 소유자는 «누가 먼저 묶었나» 로 정한다 — 나중에 만든 목표가 남의 할일을 빼앗지 않는다.
/// 이 규칙이 없으면 화면에서만 막아도 두 창이 동시에 열려 있을 때 뚫린다.
enum AchievementMemoLinkPolicy {
    /// 할일을 직접 묶는 단계. 월간·연간은 하위 목표로 진행률을 낸다.
    static let linkableCadence = "주간"

    /// 할일 → 그 할일을 이미 가진 주간 목표.
    ///
    /// - Parameter excludedGoalID: 지금 편집 중인 목표. 자기가 묶어 둔 할일은 «남의 것» 이 아니다.
    static func owners<Goal: AchievementLinkableGoal>(
        in goals: [Goal],
        excluding excludedGoalID: UUID? = nil
    ) -> [UUID: Goal] {
        var owners: [UUID: Goal] = [:]
        let candidates = goals
            .filter { $0.cadence == linkableCadence && $0.id != excludedGoalID }
            .sorted { $0.createdAt < $1.createdAt }
        for goal in candidates {
            for memoID in goal.linkedMemoIDs where owners[memoID] == nil {
                owners[memoID] = goal
            }
        }
        return owners
    }

    /// 남의 할일과 중복을 걷어낸 연결 목록. 저장 직전 마지막 방어선이다.
    ///
    /// 순서는 넘어온 그대로 둔다 — 목록 순서가 화면 정렬에 쓰이는 곳이 있어서다.
    static func sanitized<Goal: AchievementLinkableGoal>(
        linkedMemoIDs: [UUID],
        cadence: String,
        goalID: UUID?,
        existingGoals: [Goal]
    ) -> [UUID] {
        guard cadence == linkableCadence else { return linkedMemoIDs }
        let owners = owners(in: existingGoals, excluding: goalID)
        var seen = Set<UUID>()
        return linkedMemoIDs.filter { owners[$0] == nil && seen.insert($0).inserted }
    }
}

extension AchievementGoalDetail: AchievementLinkableGoal {}
