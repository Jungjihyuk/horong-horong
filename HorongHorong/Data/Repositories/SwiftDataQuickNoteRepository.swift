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

    func notes(matching query: String, limit: Int) throws -> [QuickNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var pinnedDescriptor = FetchDescriptor<Memo>(predicate: Self.pinnedSection, sortBy: Self.recentFirst)
        var restDescriptor = FetchDescriptor<Memo>(predicate: Self.unpinnedSection, sortBy: Self.recentFirst)

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

    func note(id: UUID) throws -> QuickNote? {
        try find(id).map(Self.toNote)
    }

    @discardableResult
    func add(content: String, icon: String? = nil) throws -> QuickNote {
        let memo = Memo(content: content, icon: icon, section: .quickNote)
        context.insert(memo)
        try context.save()
        return Self.toNote(memo)
    }

    func updateContent(id: UUID, content: String) throws {
        try touch(id) { $0.content = content }
    }

    func setPinned(id: UUID, isPinned: Bool) throws {
        try touch(id) { $0.isPinned = isPinned }
    }

    func promoteToTodo(id: UUID) throws {
        try touch(id) { memo in
            memo.assignSection(.todo)
            // 날짜가 하나도 없으면 Todo 목록에서 «언제» 를 못 정해 아무 묶음에도 못 들어간다.
            if memo.startDate == nil && memo.deadline == nil {
                memo.startDate = Date()
            }
        }
    }

    func delete(id: UUID) throws {
        guard let memo = try find(id) else { return }
        context.delete(memo)
        try context.save()
    }

    // MARK: - 내부

    /// 보관한 것은 목록에서 뺀다. `nil` 이 빠지지 않는 것은 `normalizeMemoFlags` 가
    /// 실행마다 `nil` 을 `false` 로 메우기 때문이다 — 그 보정이 없으면 SQL 3값 논리에 걸린다.
    private static let pinnedSection = #Predicate<Memo> {
        $0.sectionRaw == "quickNote" && $0.isArchived != true && $0.isPinned
    }

    private static let unpinnedSection = #Predicate<Memo> {
        $0.sectionRaw == "quickNote" && $0.isArchived != true && !$0.isPinned
    }

    private static let recentFirst = [SortDescriptor(\Memo.updatedAt, order: .reverse)]

    private func find(_ id: UUID) throws -> Memo? {
        var descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 고친 뒤 `updatedAt` 을 올리고 저장한다. 쓰기 메서드가 넷이라 한 곳에 모았다.
    private func touch(_ id: UUID, _ change: (Memo) -> Void) throws {
        guard let memo = try find(id) else { return }
        change(memo)
        memo.updatedAt = Date()
        try context.save()
    }

    private static func toNote(_ memo: Memo) -> QuickNote {
        QuickNote(
            id: memo.id,
            content: memo.content,
            isPinned: memo.isPinned,
            createdAt: memo.createdAt,
            updatedAt: memo.updatedAt
        )
    }
}
