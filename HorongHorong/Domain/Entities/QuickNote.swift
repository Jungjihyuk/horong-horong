import Foundation

/// 떠오르는 대로 적어둔 기록 한 건.
///
/// **값 타입이다.** 저장은 `Memo`(`@Model`)가 하지만 그건 Data 계층에 남고,
/// 화면·ViewModel 은 이 타입만 본다(`Reference` 와 같은 이유).
struct QuickNote: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    /// 고정한 기록은 목록 맨 위에 모인다. 정렬이 아니라 **묶음**이다 —
    /// `Bool` 은 `Comparable` 이 아니라 SQL 정렬 키가 될 수 없어서다.
    let isPinned: Bool
    let createdAt: Date
    let updatedAt: Date

    var title: String { NoteText.title(of: content) }
    var rest: String? { NoteText.rest(of: content) }
}
