import Foundation
import Observation

/// Quick Note 화면의 상태.
///
/// **`@Query` 를 쓰지 않는다.** «언제 다시 불러올지» 를 이 클래스가 직접 정한다
/// (`ReferencesViewModel` 과 같은 이유 — 그쪽 주석에 근거를 적어 두었다).
@MainActor
@Observable
final class QuickNoteViewModel {
    private(set) var notes: [QuickNote] = []
    private(set) var selected: QuickNote?
    private(set) var canLoadMore = false

    var searchText = "" { didSet { guard searchText != oldValue else { return }; reload() } }
    /// 위쪽 입력칸. 아직 저장되지 않은 새 기록이다.
    var composerText = ""
    /// 편집 중인 본문. **타건은 여기서 끝난다** — 저장은 아래에서 미룬다.
    var draft = ""

    private let repository: QuickNoteRepository
    private var limit = QuickNoteViewModel.pageSize
    private var saveTask: Task<Void, Never>?

    private static let pageSize = 50

    init(repository: QuickNoteRepository) {
        self.repository = repository
    }

    var canSubmitComposer: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 읽기

    func reload() {
        let requested = limit
        var loaded = (try? repository.notes(matching: searchText, limit: requested + 1)) ?? []

        // 고정한 기록은 개수 제한 없이 오므로, «더 있는지» 는 고정하지 않은 쪽만 세어 판단한다.
        // 한 건 더 청해서 그게 왔으면 더 있는 것이고, 그 한 건은 화면에서 뺀다.
        if loaded.filter({ !$0.isPinned }).count > requested,
           let extra = loaded.lastIndex(where: { !$0.isPinned }) {
            loaded.remove(at: extra)
            canLoadMore = true
        } else {
            canLoadMore = false
        }

        notes = loaded
        syncSelection()
    }

    func loadMore() {
        guard canLoadMore else { return }
        limit += Self.pageSize
        reload()
    }

    func select(_ id: UUID?) {
        flush()
        selected = id.flatMap { try? repository.note(id: $0) }
        draft = selected?.content ?? ""
    }

    // MARK: - 쓰기

    func submitComposer() {
        let content = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let created = try? repository.add(content: content) else { return }
        composerText = ""
        limit = Self.pageSize
        reload()
        selected = created
        draft = created.content
    }

    func togglePinned(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) ?? selected else { return }
        try? repository.setPinned(id: id, isPinned: !note.isPinned)
        refreshSelected(id)
        reload()
    }

    /// Todo 로 보낸다. 보낸 기록은 이 목록에서 사라지므로 선택도 옮겨진다.
    func promoteToTodo(_ id: UUID) {
        flush()
        try? repository.promoteToTodo(id: id)
        if selected?.id == id { selected = nil; draft = "" }
        reload()
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
        refreshSelected(id)
        reload()
    }

    private func refreshSelected(_ id: UUID) {
        guard selected?.id == id else { return }
        selected = try? repository.note(id: id)
    }

    /// 고른 항목이 사라졌으면(삭제·Todo 로 보냄·검색으로 걸러짐) 첫 항목으로 옮긴다.
    private func syncSelection() {
        if let selected, notes.contains(where: { $0.id == selected.id }) { return }
        selected = notes.first
        draft = selected?.content ?? ""
    }
}
