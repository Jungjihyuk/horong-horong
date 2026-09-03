import Foundation
import Observation

/// 팝오버 메모 탭의 상태.
///
/// **`@Query` 를 쓰지 않는다.** 같은 할 일을 기록·성취 화면에서도 고치므로,
/// 쓰기 뒤 재적재에 더해 나타날 때마다 다시 읽는다.
@MainActor
@Observable
final class MemoListViewModel {
    private(set) var todayTodos: [TodoItem] = []
    private(set) var upcomingTodos: [TodoItem] = []

    private let repository: TodoRepository
    private let quickNotes: QuickNoteRepository

    init(repository: TodoRepository, quickNotes: QuickNoteRepository) {
        self.repository = repository
        self.quickNotes = quickNotes
    }

    var hasRows: Bool { !todayTodos.isEmpty || !upcomingTodos.isEmpty }

    func rows(for tab: MemoListTab) -> [TodoItem] {
        tab == .today ? todayTodos : upcomingTodos
    }

    // MARK: - 읽기

    func reload() {
        let now = Date()
        let active = (try? repository.activeTodos(matching: "")) ?? []

        // 고정한 것을 위로. 정렬이 아니라 **묶음**이다 — `Bool` 은 SQL 정렬 키가 못 된다.
        let today = active.filter { $0.bucket(now: now) == .today }
        todayTodos = today.filter(\.isPinned) + today.filter { !$0.isPinned }

        // 오늘 이후로 잡힌 할 일은 가까운 것부터.
        upcomingTodos = active
            .filter { $0.bucket(now: now) == .upcoming }
            .sorted { $0.dueSortKey < $1.dueSortKey }
    }

    // MARK: - 쓰기

    func togglePinned(_ item: TodoItem) {
        try? repository.setPinned(id: item.id, isPinned: !item.isPinned)
        reload()
    }

    func toggleCompleted(_ item: TodoItem) {
        try? repository.setCompleted(id: item.id, isCompleted: !item.isCompleted)
        reload()
    }

    func setIcon(_ id: UUID, icon: String) {
        try? repository.setIcon(id: id, icon: icon)
        reload()
    }

    func updateContent(_ id: UUID, content: String) {
        try? repository.updateContent(id: id, content: content)
        reload()
    }

    /// 최근 삭제로 보낸다. 걸어둔 알림·미리알림 연동은 저장소가 함께 뗀다.
    func delete(_ id: UUID) {
        try? repository.moveToRecentlyDeleted(id: id)
        reload()
    }

    /// 「새 메모」는 **Quick Note 를 만든다.** 이 목록은 할 일만 보여주므로
    /// 방금 만든 기록은 여기 나타나지 않는다 — 기록 창의 Quick Note 에서 보인다.
    /// 섹션이 갈리기 전부터 있던 동작이다. `[확인 필요]`
    func addQuickNote(content: String, icon: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? quickNotes.add(content: content, icon: icon)
    }
}
