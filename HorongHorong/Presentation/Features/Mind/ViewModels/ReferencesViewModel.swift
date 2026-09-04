import Foundation
import Observation

/// 참고 자료 화면의 상태.
///
/// **`@Query` 를 쓰지 않는다.** 그 대신 «언제 다시 불러올지» 를 이 클래스가 직접 정한다.
/// 자동 갱신을 잃는 대신, 결과가 안 바뀌는데도 화면이 다시 그려지는 일이 없어진다.
@MainActor
@Observable
final class ReferencesViewModel {
    private(set) var references: [ReferenceItem] = []
    private(set) var selected: ReferenceItem?
    private(set) var canLoadMore = false

    var searchText = "" { didSet { guard searchText != oldValue else { return }; reload() } }
    var newContent = ""
    /// 편집 중인 본문. **타건은 여기서 끝난다** — 저장은 아래에서 미룬다.
    var draft = ""

    private let repository: ReferenceRepository
    private var limit = ReferencesViewModel.pageSize
    private var saveTask: Task<Void, Never>?

    private static let pageSize = 50

    init(repository: ReferenceRepository) {
        self.repository = repository
    }

    // MARK: - 읽기

    /// **결정 ① — 갱신은 «쓰기 뒤 명시적 재적재»로 한다.**
    ///
    /// `@Query` 는 데이터가 건드려지기만 해도 알아서 다시 가져왔다. 편했지만 결과가
    /// 그대로일 때도 화면 전체를 다시 그렸다(실측: 20초 타이핑에 body 70회).
    /// 여기서는 **바뀐 것을 아는 쪽(쓰기 메서드)이 재적재를 부른다.**
    ///
    /// 다른 화면의 변경까지 받아야 하면 그때 저장소가 알림을 발행하는 방식을 더한다.
    /// 참고 자료는 이 화면에서만 바뀌므로 지금은 필요 없다.
    func reload() {
        let requested = limit
        references = (try? repository.references(matching: searchText, limit: requested + 1)) ?? []
        canLoadMore = references.count > requested
        if canLoadMore { references.removeLast() }
        syncSelection()
    }

    /// **결정 ② — 페이징은 오프셋 방식(개수 늘리기)으로 한다.**
    ///
    /// 커서 방식을 쓰려면 정렬 키가 변하지 않아야 하는데, 이 목록은 «최근에 고친 순» 이라
    /// **편집할 때마다 항목이 맨 위로 이동한다.** 커서가 가리키던 자리가 사라진다.
    ///
    /// 오프셋의 약점(보는 사이에 앞에 끼어들면 한 칸 밀림)은 쓰기 직후 처음부터 다시
    /// 읽는 것으로 줄인다. 정렬 키가 고정된 목록을 옮길 때는 커서를 다시 검토한다.
    func loadMore() {
        guard canLoadMore else { return }
        limit += Self.pageSize
        reload()
    }

    func select(_ id: UUID?) {
        flush()
        selected = id.flatMap { try? repository.reference(id: $0) }
        draft = selected?.content ?? ""
    }

    // MARK: - 쓰기

    func add() {
        let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let created = try? repository.add(content: content) else { return }
        newContent = ""
        limit = Self.pageSize
        reload()
        selected = created
        draft = created.content
    }

    func delete(_ id: UUID) {
        flush()
        try? repository.delete(id: id)
        if selected?.id == id { selected = nil; draft = "" }
        reload()
    }

    /// 타건마다 저장하지 않는다. 저장은 400ms 뒤 한 번.
    func draftChanged() {
        guard let id = selected?.id else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            persist(id)
        }
    }

    /// 화면을 벗어나거나 선택을 바꾸기 전에 미뤄둔 저장을 마무리한다.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        if let id = selected?.id { persist(id) }
    }

    // MARK: - 내부

    private func persist(_ id: UUID) {
        guard draft != selected?.content else { return }
        try? repository.updateContent(id: id, content: draft)
        selected = try? repository.reference(id: id)
        reload()
    }

    /// 고른 항목이 사라졌으면(삭제·검색으로 걸러짐) 첫 항목으로 옮긴다.
    private func syncSelection() {
        if let selected, references.contains(where: { $0.id == selected.id }) { return }
        selected = references.first
        draft = selected?.content ?? ""
    }
}
