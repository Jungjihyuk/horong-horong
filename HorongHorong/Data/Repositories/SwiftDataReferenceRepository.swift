import Foundation
import SwiftData

/// `ReferenceRepository` 의 SwiftData 구현.
///
/// **`@MainActor` 인 이유**: 참고 자료는 화면에 보이는 만큼(50건)만 가져오므로 메인 스레드에서
/// 끝난다. 백그라운드 `ModelActor` 는 그것으로 부족한 화면(Todo·Stats)에서 도입한다 —
/// 지금 넣으면 얻는 것 없이 동시성 복잡도만 는다.
@MainActor
final class SwiftDataReferenceRepository: ReferenceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func references(matching query: String, limit: Int) throws -> [ReferenceItem] {
        var descriptor = FetchDescriptor<Reference>(
            // 화면 정렬과 DB 정렬을 같게 맞춘다. 다르면 앞 50건을 가져온 뒤 다시 정렬하게 되어
            // 51번째에 있는 항목이 위로 올라오지 못한다.
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map(Self.toReference)
        }

        // 검색 중에는 개수를 제한하지 않는다. `localizedCaseInsensitiveContains` 는
        // SQL 로 번역되지 않아 앱에서 걸러야 하는데, 앞 50건만 가져와 거르면
        // **51번째부터는 검색해도 안 나온다.**
        return try context.fetch(descriptor)
            .filter { $0.content.localizedCaseInsensitiveContains(trimmed) }
            .prefix(limit)
            .map(Self.toReference)
    }

    func reference(id: UUID) throws -> ReferenceItem? {
        try find(id).map(Self.toReference)
    }

    @discardableResult
    func add(content: String) throws -> ReferenceItem {
        let record = Reference(content: content)
        context.insert(record)
        try context.save()
        return Self.toReference(record)
    }

    func updateContent(id: UUID, content: String) throws {
        guard let record = try find(id) else { return }
        record.content = content
        record.updatedAt = Date()
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try find(id) else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - 내부

    private func find(_ id: UUID) throws -> Reference? {
        var descriptor = FetchDescriptor<Reference>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// `@Model` → 값 타입 변환.
    private static func toReference(_ record: Reference) -> ReferenceItem {
        ReferenceItem(id: record.id, content: record.content, updatedAt: record.updatedAt)
    }
}
