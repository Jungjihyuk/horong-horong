import Foundation

/// 미리알림 앱의 항목을 메모로 가져오고 되돌린다. 구현은 `Data/Repositories/` 에 있다.
///
/// **가져오기는 한 방향이다.** 미리알림 앱이 원본이고 이 앱은 사본을 만든다 —
/// 되돌릴 때도 사본만 지우고 원본은 건드리지 않는다.
@MainActor
protocol ReminderImportRepository {
    /// 선택 해제된 목록에 묶여 있는 메모. 「되돌리기」 대상이다.
    func memosLinkedToUnselectedCalendars(selectedCalendarIDs: Set<String>) -> [ImportedReminderMemo]

    /// 아직 안 가져온 것만 메모로 만든다. 반환값은 새로 만든 개수.
    ///
    /// **두 번 가져오지 않는다** — 이미 있는 `reminderIdentifier` 는 건너뛴다.
    /// 시작·마감이 비어 있으면 지난 기록에서 걸린 시간을 추정해 채운다.
    @discardableResult
    func importReminders(_ items: [ReminderListItem]) throws -> Int

    /// 가져온 메모를 지운다. 걸어둔 알림도 함께 뗀다.
    func deleteImportedMemos(ids: [UUID]) throws
}

/// 되돌리기 목록에 보여줄 최소 정보.
struct ImportedReminderMemo: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    let reminderCalendarIdentifier: String?
}
