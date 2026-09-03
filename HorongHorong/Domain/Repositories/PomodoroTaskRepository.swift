import Foundation

/// 뽀모도로를 시작할 때 고를 할일 후보를 읽는다. 구현은 `Data/Repositories/` 에 있다.
///
/// **읽기만 한다.** 타이머가 할일을 고치지는 않는다 — 고르기만 하고, 완료 표시는
/// 기록·성취 화면에서 한다.
@MainActor
protocol PomodoroTaskRepository {
    /// 후보가 될 수 있는 할일 — 안 끝났고 보관·삭제되지 않은 것.
    ///
    /// 「오늘 것인가」와 「목표에 걸렸는가」를 가리는 일은 `PomodoroTaskCandidateBuilder`
    /// 가 한다. 그건 «지금» 기준 계산이라 SQL 로 표현할 수 없다.
    func candidateMemos() -> [AchievementMemoDetail]

    /// 목표에 묶인 할일 id 전부. 후보를 «목표에 걸린 일» 로 표시할 때 쓴다.
    func goalLinkedMemoIDs() -> Set<UUID>
}
