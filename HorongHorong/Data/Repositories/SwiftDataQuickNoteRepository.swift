import Foundation
import SwiftData

/// `QuickNoteRepository` 의 SwiftData 구현.
///
/// **`@MainActor` 인 이유**: 화면에 보이는 만큼(50건)만 가져오므로 메인 스레드에서 끝난다
/// (`SwiftDataReferenceRepository` 와 같은 판단).
@MainActor
final class SwiftDataQuickNoteRepository: QuickNoteRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func notes(matching query: String, limit: Int) throws -> [QuickNoteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var pinnedDescriptor = FetchDescriptor<QuickNote>(predicate: Self.pinnedSection, sortBy: Self.recentFirst)
        var restDescriptor = FetchDescriptor<QuickNote>(predicate: Self.unpinnedSection, sortBy: Self.recentFirst)

        // 검색 중에는 개수를 제한하지 않는다. `localizedCaseInsensitiveContains` 는
        // SQL 로 번역되지 않아 앱에서 걸러야 하는데, 앞 50건만 가져와 거르면
        // **51번째부터는 검색해도 안 나온다.**
        if trimmed.isEmpty {
            pinnedDescriptor.fetchLimit = limit
            restDescriptor.fetchLimit = limit
        }

        let pinned = try context.fetch(pinnedDescriptor)
        let rest = try context.fetch(restDescriptor)

        guard !trimmed.isEmpty else {
            return (pinned + rest).map(Self.toNote)
        }
        return (pinned + rest)
            .filter { $0.content.localizedCaseInsensitiveContains(trimmed) }
            .prefix(limit)
            .map(Self.toNote)
    }

    func note(id: UUID) throws -> QuickNoteItem? {
        try find(id).map(Self.toNote)
    }

    @discardableResult
    func add(content: String, icon: String? = nil) throws -> QuickNoteItem {
        let record = QuickNote(content: content, icon: icon)
        context.insert(record)
        try context.save()
        return Self.toNote(record)
    }

    func updateContent(id: UUID, content: String) throws {
        try touch(id) { $0.content = content }
    }

    func setPinned(id: UUID, isPinned: Bool) throws {
        try touch(id) { $0.isPinned = isPinned }
    }

    func promoteToTodo(id: UUID) throws {
        guard let note = try find(id) else { return }
        let todo = Todo(
            id: note.id,
            content: note.content,
            icon: note.icon,
            createdAt: note.createdAt,
            updatedAt: Date(),
            isPinned: note.isPinned,
            startDate: Date()
        )
        context.insert(todo)
        context.delete(note)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try find(id) else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - 내부

    private static let pinnedSection = #Predicate<QuickNote> {
        $0.isPinned
    }

    private static let unpinnedSection = #Predicate<QuickNote> {
        !$0.isPinned
    }

    private static let recentFirst = [SortDescriptor(\QuickNote.updatedAt, order: .reverse)]

    private func find(_ id: UUID) throws -> QuickNote? {
        var descriptor = FetchDescriptor<QuickNote>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 고친 뒤 `updatedAt` 을 올리고 저장한다. 쓰기 메서드가 넷이라 한 곳에 모았다.
    private func touch(_ id: UUID, _ change: (QuickNote) -> Void) throws {
        guard let record = try find(id) else { return }
        change(record)
        record.updatedAt = Date()
        try context.save()
    }

    private static func toNote(_ record: QuickNote) -> QuickNoteItem {
        QuickNoteItem(
            id: record.id,
            content: record.content,
            isPinned: record.isPinned,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
