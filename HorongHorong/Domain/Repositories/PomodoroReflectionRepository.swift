import Foundation

/// 집중이 끝난 뒤의 회고를 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **회고 저장은 한 덩어리다.** 답을 남기고, 연결된 할 일을 완료로 찍고, 관련 화면에
/// 알린다 — 중간에 실패하면 전부 되돌린다. 그 되돌리기(`rollback`)를 화면이 다루면
/// 「어디까지 저장됐나」를 화면이 알아야 한다.
@MainActor
protocol PomodoroReflectionRepository {
    /// 회고 창을 띄우기 전에 필요한 것. **이미 답한 세션이면 `nil`** — 두 번 묻지 않는다.
    func prompt(for sessionID: UUID) -> PomodoroReflectionPrompt?

    /// 회고를 저장한다. 계획대로 끝냈고 할 일이 연결돼 있으면 그 할 일도 완료로 찍는다.
    func saveReflection(
        sessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?,
        answeredAt: Date
    ) throws

    /// 분류하지 못한 앱들에 사용자가 고른 카테고리를 적용한다.
    func saveClassification(
        sessionID: UUID,
        choices: [String: UnclassifiedAppChoice],
        apps: [UnclassifiedAppUsage],
        productivityManagementAppCategories: [String: String]
    ) throws

    /// 「나중에 쓰기」. 그 시각을 찍어 두면 나중에 다시 물을 수 있다.
    func deferReflection(sessionID: UUID, at date: Date) throws
}

/// 회고 창이 그리는 데 필요한 값들.
struct PomodoroReflectionPrompt: Equatable, Sendable {
    let sessionID: UUID
    /// 연결된 할 일의 제목 스냅샷. 없으면 `nil`.
    let taskTitle: String?
    let isLinkedTask: Bool
    /// 계획대로 끝냈을 때 연결된 할 일을 완료로 찍을 수 있는가.
    ///
    /// `isLinkedTask` 와 다르다 — 연결은 돼 있는데 그 할 일이 이미 지워졌을 수 있다.
    let canRecordLinkedTaskCompletion: Bool
    /// 분류 질문의 기본값으로 쓸 카테고리. 이 세션의 카테고리다.
    let suggestedAppCategory: String
    /// 카테고리를 못 정한 앱들. 비어 있으면 분류 질문을 건너뛴다.
    let unclassifiedApps: [UnclassifiedAppUsage]
    let unclassifiedRatio: Double?
    let productivityManagementAppUsages: [ProductivityManagementAppUsage]
}
