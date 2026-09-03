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

    func references(matching query: String, limit: Int) throws -> [Reference] {
        var descriptor = FetchDescriptor<SecondBrainRecord>(
            predicate: Self.referenceSection,
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

    func reference(id: UUID) throws -> Reference? {
        try find(id).map(Self.toReference)
    }

    @discardableResult
    func add(content: String) throws -> Reference {
        let record = SecondBrainRecord(content: content, section: .reference)
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

    /// 보관한 것은 목록에서 뺀다. `nil` 이 빠지지 않는 것은 `normalizeMemoFlags` 가
    /// 실행마다 `nil` 을 `false` 로 메우기 때문이다 — 그 보정이 없으면 SQL 3값 논리에 걸린다.
    private static let referenceSection = #Predicate<SecondBrainRecord> {
        $0.sectionRaw == "reference"
    }

    private func find(_ id: UUID) throws -> SecondBrainRecord? {
        var descriptor = FetchDescriptor<SecondBrainRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// `@Model` → 값 타입 변환.
    ///
    /// **별도 `Mapper` 파일로 빼지 않았다.** 지금은 이 Repository 만 쓰는 네 줄이라,
    /// 파일을 늘리면 읽을 것만 는다. 같은 매핑을 두 곳 이상이 쓰게 되면 그때
    /// `Data/Mappers/ReferenceMapper.swift` 로 뺀다(CLAUDE.md §3 «두 개 이상일 때 분리»).
    private static func toReference(_ record: SecondBrainRecord) -> Reference {
        Reference(id: record.id, content: record.content, updatedAt: record.updatedAt)
    }
}
