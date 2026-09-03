import Foundation

/// 집중 세션을 기록한다. 구현은 `Data/Repositories/` 에 있다.
///
/// **타이머 자체는 여기 없다.** 남은 시간을 세고 알림을 띄우는 일은 `TimerManager` 가 하고,
/// 이 계약은 「시작했다 · 멈췄다 · 끝냈다」를 남기는 일만 맡는다.
///
/// 메서드가 `id` 를 받는 이유: 진행 중인 세션을 `@Model` 로 들고 있으면 그게 화면 쪽
/// 클래스까지 새어 나온다. 부르는 쪽은 식별자만 든다.
@MainActor
protocol FocusSessionRepository {
    /// 새 집중을 시작한다. 반환값은 그 세션의 식별자.
    func startFocus(
        focusMinutes: Int,
        breakMinutes: Int,
        category: String?,
        linkedMemoID: UUID?,
        taskTitleSnapshot: String?
    ) -> UUID

    func recordPauseStarted(id: UUID, at date: Date)
    func recordPauseEnded(id: UUID, at date: Date)

    /// 집중을 끝내고 통계에 반영한다.
    ///
    /// **통계 반영까지 여기서 하는 이유**: 「끝냈으면 그날 집중 시간에 더한다」는 규칙이
    /// 끝내는 경로 두 곳(직접 종료·타이머 완료)에 각각 복사돼 있었다.
    ///
    /// 반환값은 「이어서 같은 일을 할 수 있는가」를 판단할 재료다.
    @discardableResult
    func finishFocus(
        id: UUID,
        endedAt: Date,
        actualSeconds: Int,
        inputActiveSeconds: Int,
        endKind: FocusSessionEndKind
    ) -> FinishedFocusSession?

    /// 기록하지 않고 버린다. 세션 자체가 사라진다.
    func discardFocus(id: UUID)

    /// 완료로 치지 않고 끝만 찍는다(`reset`). 이미 완료된 세션은 건드리지 않는다.
    func abandonFocus(id: UUID, endedAt: Date)

    /// 이 시각 이후에 시작한 집중이 있는가. 쉬는 시간 뒤 안내를 띄울지 정할 때 쓴다.
    func hasFocusSession(startingAfter date: Date) -> Bool

    /// 그 할 일이 아직 살아 있는가. 끝났거나 지워졌으면 «이어서 하기» 를 권하지 않는다.
    func isTaskStillOpen(memoID: UUID?) -> Bool

    /// 이 시각 이후로 생산적인 앱을 `minimumSeconds` 이상 썼는가.
    func hasProductiveActivity(since date: Date, minimumSeconds: Int) -> Bool

    func recordBreakTransition(
        breakEndedAt: Date,
        decision: BreakTransitionDecisionKind,
        previousCategory: String,
        nextCategory: String?
    )
}

/// 끝난 세션에서 «다음에 이어서 할 일» 을 정하는 데 필요한 것만.
struct FinishedFocusSession: Equatable, Sendable {
    let id: UUID
    let linkedMemoID: UUID?
    let taskTitleSnapshot: String?
    /// 연결된 할 일이 아직 살아 있는가. 저장소가 판단해 넣어 준다.
    let isTaskStillOpen: Bool
}
