import Foundation

/// 할 일 한 건.
///
/// **값 타입이다.** 저장은 `Memo`(`@Model`)가 하지만 그건 Data 계층에 남고,
/// 화면·ViewModel 은 이 타입만 본다.
struct TodoItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    let startDate: Date?
    let deadline: Date?
    let isCompleted: Bool
    /// 최근 삭제에 들어간 시각. `nil` 이면 살아 있다.
    let deletedAt: Date?
    let isLinkedToReminders: Bool
    let reminderCalendarIdentifier: String?
    /// 팝오버 목록이 쓰는 것들. 상세 화면에는 안 나온다.
    let icon: String?
    let isPinned: Bool
    let createdAt: Date
    let updatedAt: Date
    /// 보관한 할 일. 목록에서는 빠지지만 **연결 고르기** 에서는 보인다 —
    /// 예전에 연결해 둔 것을 찾을 수 있어야 한다.
    let isArchived: Bool

    var isRecentlyDeleted: Bool { deletedAt != nil }

    /// **`NoteText` 를 쓰지 않는 이유**: 할 일은 «첫 줄 = 제목, 나머지 = 메모» 를 편집기에서
    /// 나눠 보여주고 다시 합친다. 빈 줄을 건너뛰면 되돌릴 때 원문이 달라진다 —
    /// 여기서는 첫 줄바꿈에서 **그대로** 자른다.
    var split: (title: String, note: String) {
        guard let index = content.firstIndex(of: "\n") else { return (content, "") }
        return (String(content[..<index]), String(content[content.index(after: index)...]))
    }

    /// 목록에 보일 제목. 비어 있으면 «제목 없음».
    var displayTitle: String {
        let title = split.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없음" : title
    }

    func bucket(now: Date) -> TodoBucket {
        TodoBucket.of(startDate: startDate, deadline: deadline, isCompleted: isCompleted, now: now)
    }

    /// 그룹 안 정렬 키. 날짜가 없으면 맨 뒤로 간다.
    var dueSortKey: Date { deadline ?? startDate ?? .distantFuture }

    /// 본문에서 제목과 메모를 합친다. 편집기가 두 칸을 하나로 되돌릴 때 쓴다.
    static func joined(title: String, note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : title + "\n" + note
    }
}
