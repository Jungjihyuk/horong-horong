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

    var searchText = "" { didSet { guard searchText != oldValue else { return }; resetPaging() } }
    /// `nil` 이면 «전체». 검색과 같은 방식으로 다시 읽는다.
    var mode: ReferenceKind? { didSet { guard mode != oldValue else { return }; resetPaging() } }

    /// 편집 중인 값. **타건은 여기서 끝난다** — 저장은 아래에서 미룬다.
    var titleDraft = ""
    var urlDraft = ""
    var bodyDraft = ""

    private let repository: ReferenceRepository
    private var limit = ReferencesViewModel.pageSize
    private var saveTask: Task<Void, Never>?

    private static let pageSize = 50

    init(repository: ReferenceRepository) {
        self.repository = repository
    }

    /// 목록 부제에 쓰는 값.
    var widgetCount: Int { references.count { $0.isWidget } }

    // MARK: - 읽기

    func reload() {
        let requested = limit
        references = (try? repository.references(matching: searchText, kind: mode, limit: requested + 1)) ?? []
        canLoadMore = references.count > requested
        if canLoadMore { references.removeLast() }
        syncSelection()
    }

    /// 페이징은 오프셋 방식(개수 늘리기)이다. 커서 방식은 «최근에 고친 순» 정렬이라
    /// 편집할 때마다 항목이 맨 위로 이동해 못 쓴다.
    func loadMore() {
        guard canLoadMore else { return }
        limit += Self.pageSize
        reload()
    }

    func select(_ id: UUID?) {
        flush()
        selected = id.flatMap { try? repository.reference(id: $0) }
        loadDrafts()
    }

    /// 위젯 창이나 다른 화면이 같은 항목을 고쳤을 때 다시 읽는다.
    func refreshExternally(id: UUID) {
        if selected?.id == id {
            selected = try? repository.reference(id: id)
            loadDrafts()
        }
        reload()
    }

    // MARK: - 쓰기

    func add(kind: ReferenceKind) {
        flush()
        guard let created = try? repository.add(kind: kind) else { return }
        // 새로 만든 것이 걸러져 안 보이면 «추가했는데 아무 일도 안 났다» 가 된다.
        if mode != nil, mode != kind { mode = kind }
        searchText = ""
        limit = Self.pageSize
        reload()
        selected = created
        loadDrafts()
    }

    func delete(_ id: UUID) {
        saveTask?.cancel()
        saveTask = nil
        try? repository.delete(id: id)
        if selected?.id == id { selected = nil; loadDrafts() }
        reload()
    }

    func setColor(_ color: ReferenceNoteColor) {
        apply(ReferenceChange(color: color))
    }

    func setWidget(_ isWidget: Bool) {
        apply(ReferenceChange(isWidget: isWidget))
    }

    /// 타건마다 저장하지 않는다. 저장은 400ms 뒤 한 번.
    func draftChanged() {
        guard selected != nil else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistDrafts()
        }
    }

    /// 화면을 벗어나거나 선택을 바꾸기 전에 미뤄둔 저장을 마무리한다.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persistDrafts()
    }

    // MARK: - 내부

    private func resetPaging() {
        limit = Self.pageSize
        reload()
    }

    private func loadDrafts() {
        titleDraft = selected?.title ?? ""
        urlDraft = selected?.url ?? ""
        bodyDraft = selected?.body ?? ""
    }

    private func persistDrafts() {
        guard let selected else { return }
        var change = ReferenceChange()
        if titleDraft != selected.title { change.title = titleDraft }
        if selected.kind == .link, urlDraft != (selected.url ?? "") { change.url = urlDraft }
        if selected.kind == .note, bodyDraft != selected.body { change.body = bodyDraft }
        guard change != ReferenceChange() else { return }
        apply(change)
    }

    private func apply(_ change: ReferenceChange) {
        guard let id = selected?.id else { return }
        guard let updated = try? repository.update(id: id, change) else { return }
        selected = updated
        reload()
        ReferenceChangeBroadcast.post(id: id)
    }

    /// 고른 항목이 사라졌으면(삭제·검색으로 걸러짐) 첫 항목으로 옮긴다.
    private func syncSelection() {
        if let selected, references.contains(where: { $0.id == selected.id }) { return }
        selected = references.first
        loadDrafts()
    }
}
