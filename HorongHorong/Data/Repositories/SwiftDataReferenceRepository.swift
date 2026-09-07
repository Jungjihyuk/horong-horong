import Foundation
import SwiftData

/// `ReferenceRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataReferenceRepository: ReferenceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func references(matching query: String, kind: ReferenceKind?, limit: Int) throws -> [ReferenceItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<Reference>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        // 검색어가 없으면 개수를 DB 에서 자른다. 있으면 `localizedCaseInsensitiveContains` 가
        // SQL 로 번역되지 않아 전량을 가져와 걸러야 한다 — 예전 구현과 같은 절충이다.
        guard !trimmed.isEmpty || kind != nil else {
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map(Self.toItem)
        }

        let rows = try context.fetch(descriptor)
        return rows
            .filter { kind == nil || $0.kind == kind }
            .filter { trimmed.isEmpty || Self.matches($0, query: trimmed) }
            .prefix(limit)
            .map(Self.toItem)
    }

    func reference(id: UUID) throws -> ReferenceItem? {
        try find(id).map(Self.toItem)
    }

    @discardableResult
    func add(kind: ReferenceKind) throws -> ReferenceItem {
        let entry = Reference(kindRaw: kind.rawValue, colorRaw: ReferenceNoteColor.fallback.rawValue)
        context.insert(entry)
        try context.save()
        return Self.toItem(entry)
    }

    @discardableResult
    func addLink(title: String, url: String) throws -> ReferenceItem {
        let entry = Reference(kindRaw: ReferenceKind.link.rawValue, colorRaw: ReferenceNoteColor.fallback.rawValue)
        entry.title = title
        entry.url = url
        context.insert(entry)
        try context.save()
        return Self.toItem(entry)
    }

    @discardableResult
    func update(id: UUID, _ change: ReferenceChange) throws -> ReferenceItem? {
        guard let entry = try find(id) else { return nil }
        if let title = change.title { entry.title = title }
        if let url = change.url { entry.url = url }
        if let body = change.body { entry.body = body }
        if let color = change.color { entry.colorRaw = color.rawValue }
        if let isWidget = change.isWidget { entry.isWidget = isWidget }
        if let position = change.widgetPosition {
            entry.widgetX = position.x
            entry.widgetY = position.y
        }
        if let size = change.widgetSize {
            entry.widgetWidth = size.width
            entry.widgetHeight = size.height
        }
        if let collapsed = change.isWidgetCollapsed { entry.widgetCollapsed = collapsed }
        if let behind = change.isWidgetBehind { entry.widgetBehind = behind }
        // 창을 옮긴 것만으로 «최근에 고친 항목» 순서가 뒤집히면 목록이 멋대로 재배열된다.
        if change.isOrderAffecting { entry.updatedAt = Date() }
        try context.save()
        return Self.toItem(entry)
    }

    func delete(id: UUID) throws {
        guard let entry = try find(id) else { return }
        context.delete(entry)
        try context.save()
    }

    func widgetNotes() throws -> [ReferenceItem] {
        let descriptor = FetchDescriptor<Reference>(
            predicate: #Predicate { $0.isWidget == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        // 갈래는 계산값이라 predicate 로 거를 수 없다. 꺼내 둔 항목만 오므로 양이 적다.
        return try context.fetch(descriptor)
            .filter { $0.kind == .note }
            .map(Self.toItem)
    }

    // MARK: - 내부

    private func find(_ id: UUID) throws -> Reference? {
        var descriptor = FetchDescriptor<Reference>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 제목·주소·본문 어디에 걸려도 찾은 것으로 친다. 백필 전 행을 위해 `content` 도 본다.
    private static func matches(_ entry: Reference, query: String) -> Bool {
        let haystack = [entry.title, entry.url, entry.body, entry.content]
            .compactMap { $0 }
            .joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private static func toItem(_ entry: Reference) -> ReferenceItem {
        ReferenceItem(
            id: entry.id,
            kind: entry.kind,
            // 백필 전 행은 저장된 제목이 없다. 옛 규칙(첫 줄)으로 읽어 빈 카드를 막는다.
            title: entry.title ?? NoteText.title(of: entry.content),
            url: entry.url ?? (entry.kind == .link ? MemoClassifier.firstURL(in: entry.content)?.absoluteString : nil),
            body: entry.body ?? (entry.kind == .note ? entry.content : ""),
            color: entry.noteColor,
            isWidget: entry.isWidget ?? false,
            widgetPosition: entry.widgetPosition,
            widgetSize: entry.widgetSize,
            isWidgetCollapsed: entry.widgetCollapsed ?? false,
            isWidgetBehind: entry.widgetBehind ?? false,
            updatedAt: entry.updatedAt
        )
    }
}

private extension ReferenceChange {
    /// 목록 순서를 바꿔야 하는 변경인가. 창을 옮긴 것은 내용이 바뀐 것이 아니다.
    var isOrderAffecting: Bool {
        title != nil || url != nil || body != nil || color != nil
    }
}
