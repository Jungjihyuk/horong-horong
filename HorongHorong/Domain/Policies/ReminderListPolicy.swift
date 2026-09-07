import Foundation

/// 할 일이 **어느 미리알림 목록에 속하는지** 정한다.
///
/// 두 화면(할 일 상세, 팝오버 기록 탭)이 같은 답을 내야 하므로 규칙을 한 곳에 둔다.
/// 목록 자체는 OS 에서 오지만 «어느 것을 고를지» 는 순수 계산이라 여기서 검사할 수 있다.
enum ReminderListPolicy {
    /// 저장된 식별자가 먼저다. 식별자가 없거나 이미 사라진 목록을 가리키면,
    /// **연동된 할 일에 한해** 기본 목록으로 본다 — 미리알림 앱이 거기에 넣기 때문이다.
    /// 연동되지 않은 할 일은 어느 목록에도 속하지 않는다.
    static func list(
        for item: TodoItem,
        in lists: [ReminderListOption]
    ) -> ReminderListOption? {
        if let id = item.reminderCalendarIdentifier,
           let list = lists.first(where: { $0.id == id }) {
            return list
        }
        return item.isLinkedToReminders ? lists.first(where: \.isDefault) : nil
    }
}
