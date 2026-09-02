import Foundation

/// 미리알림 앱의 목록 하나.
///
/// **Domain 에 있는 이유**: `TodoRepository` 계약에 등장한다. 값 타입이고 EventKit 타입을
/// 들고 있지 않아 계층을 넘어도 안전하다 — 실제 EventKit 변환은
/// `MemoReminderLinkService`(Data 쪽)가 한다.
struct ReminderListOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let isDefault: Bool
}
