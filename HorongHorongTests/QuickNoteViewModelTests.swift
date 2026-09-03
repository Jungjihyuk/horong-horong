import XCTest
@testable import 호롱호롱

/// **화면을 띄우지 않고** 목록 로직을 검사한다(`ReferencesViewModelTests` 와 같은 방식).
@MainActor
final class QuickNoteViewModelTests: XCTestCase {
    /// 저장소를 흉내 내는 가짜. SwiftData 도 파일도 쓰지 않는다.
    ///
    /// **실제 구현과 같은 규칙을 지킨다** — 고정한 것 먼저, `limit` 은 고정하지 않은 쪽에만.
    /// 이걸 어기면 테스트가 통과해도 실기에서 다르게 동작한다.
    private final class FakeRepository: QuickNoteRepository {
        var items: [QuickNote] = []
        private(set) var fetchCount = 0

        func notes(matching query: String, limit: Int) throws -> [QuickNote] {
            fetchCount += 1
            let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
            let pinned = sorted.filter(\.isPinned)
            let rest = sorted.filter { !$0.isPinned }

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return Array(pinned.prefix(limit)) + Array(rest.prefix(limit))
            }
            return Array(
                (pinned + rest)
                    .filter { $0.content.localizedCaseInsensitiveContains(trimmed) }
                    .prefix(limit)
            )
        }

        func note(id: UUID) throws -> QuickNote? { items.first { $0.id == id } }

        @discardableResult
        func add(content: String, icon: String?) throws -> QuickNote {
            let made = QuickNote(id: UUID(), content: content, isPinned: false, createdAt: Date(), updatedAt: Date())
            items.append(made)
            return made
        }

        func updateContent(id: UUID, content: String) throws {
            replace(id) { QuickNote(id: id, content: content, isPinned: $0.isPinned, createdAt: $0.createdAt, updatedAt: Date()) }
        }

        func setPinned(id: UUID, isPinned: Bool) throws {
            replace(id) { QuickNote(id: id, content: $0.content, isPinned: isPinned, createdAt: $0.createdAt, updatedAt: Date()) }
        }

        /// Todo 로 간 기록은 Quick Note 목록에서 사라진다 — 가짜에서는 지우는 것으로 흉내 낸다.
        func promoteToTodo(id: UUID) throws { items.removeAll { $0.id == id } }

        func delete(id: UUID) throws { items.removeAll { $0.id == id } }

        private func replace(_ id: UUID, _ change: (QuickNote) -> QuickNote) {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index] = change(items[index])
        }
    }

    /// `pinned` 는 **가장 오래된** 시각을 받는다. 개수 제한이 고정에도 걸리면 첫 쪽에서
    /// 밀려나야 하므로, 안 밀려나는 것이 곧 «고정은 페이징하지 않는다» 의 검증이 된다.
    private func make(unpinned: Int, pinned: Int = 0) -> (QuickNoteViewModel, FakeRepository) {
        let repository = FakeRepository()
        let base = Date()
        repository.items =
            (0..<pinned).map {
                QuickNote(
                    id: UUID(), content: "고정 \($0)", isPinned: true,
                    createdAt: base, updatedAt: base.addingTimeInterval(Double($0) - 10_000)
                )
            }
            + (0..<unpinned).map {
                QuickNote(
                    id: UUID(), content: "기록 \($0)", isPinned: false,
                    createdAt: base, updatedAt: base.addingTimeInterval(Double($0))
                )
            }
        return (QuickNoteViewModel(repository: repository), repository)
    }

    func testLoadsFirstPageOnly() {
        let (viewModel, _) = make(unpinned: 130)
        viewModel.reload()

        XCTAssertEqual(viewModel.notes.count, 50)
        XCTAssertTrue(viewModel.canLoadMore)
    }

    func testLoadMoreGrowsPage() {
        let (viewModel, _) = make(unpinned: 130)
        viewModel.reload()
        viewModel.loadMore()

        XCTAssertEqual(viewModel.notes.count, 100)
        XCTAssertTrue(viewModel.canLoadMore)

        viewModel.loadMore()
        XCTAssertEqual(viewModel.notes.count, 130)
        XCTAssertFalse(viewModel.canLoadMore, "더 없으면 더 청하지 않는다")
    }

    func testExactPageSizeDoesNotOfferMore() {
        let (viewModel, _) = make(unpinned: 50)
        viewModel.reload()

        XCTAssertEqual(viewModel.notes.count, 50)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    /// 고정한 기록은 아무리 오래된 것이어도 첫 쪽에 있고, 개수 계산에도 안 낀다.
    func testPinnedAlwaysOnTopAndNotPaged() {
        let (viewModel, _) = make(unpinned: 130, pinned: 3)
        viewModel.reload()

        XCTAssertEqual(viewModel.notes.prefix(3).filter(\.isPinned).count, 3, "고정이 맨 위")
        XCTAssertEqual(viewModel.notes.count, 53, "고정 3 + 한 쪽 50")
        XCTAssertTrue(viewModel.canLoadMore, "고정이 «더 있음» 판단을 흐리면 안 된다")
    }

    func testSearchTextTriggersReload() {
        let (viewModel, repository) = make(unpinned: 10)
        viewModel.reload()
        let before = repository.fetchCount

        viewModel.searchText = "기록 3"

        XCTAssertGreaterThan(repository.fetchCount, before)
        XCTAssertEqual(viewModel.notes.count, 1)
    }

    /// 추가하면 목록이 스스로 갱신된다(`@Query` 없이).
    func testSubmitComposerRefreshesListAndSelects() {
        let (viewModel, _) = make(unpinned: 3)
        viewModel.reload()

        viewModel.composerText = "치과 예약"
        viewModel.submitComposer()

        XCTAssertEqual(viewModel.notes.count, 4)
        XCTAssertEqual(viewModel.selected?.content, "치과 예약")
        XCTAssertEqual(viewModel.composerText, "", "입력칸은 비운다")
    }

    func testBlankComposerIsIgnored() {
        let (viewModel, _) = make(unpinned: 2)
        viewModel.reload()

        viewModel.composerText = "   \n  "
        viewModel.submitComposer()

        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertFalse(viewModel.canSubmitComposer)
    }

    func testTogglePinnedMovesNoteToTop() {
        let (viewModel, _) = make(unpinned: 5)
        viewModel.reload()
        let last = try! XCTUnwrap(viewModel.notes.last)

        viewModel.togglePinned(last.id)

        XCTAssertEqual(viewModel.notes.first?.id, last.id)
        XCTAssertEqual(viewModel.notes.first?.isPinned, true)
    }

    /// Todo 로 보내면 이 목록에서 사라지고 선택이 옮겨진다.
    func testPromoteToTodoRemovesFromList() {
        let (viewModel, _) = make(unpinned: 3)
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.notes.first)

        viewModel.promoteToTodo(target.id)

        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertFalse(viewModel.notes.contains { $0.id == target.id })
        XCTAssertNotEqual(viewModel.selected?.id, target.id)
        XCTAssertNotNil(viewModel.selected)
    }

    func testDeletingLastLeavesNoSelection() {
        let (viewModel, _) = make(unpinned: 1)
        viewModel.reload()
        let only = try! XCTUnwrap(viewModel.notes.first)

        viewModel.delete(only.id)

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertNil(viewModel.selected)
        XCTAssertEqual(viewModel.draft, "")
    }

    /// 제목·나머지 줄 규칙은 `NoteText` 한 곳에 있다. Quick Note 와 References 가 같이 쓴다.
    func testNoteTextRules() {
        let note = QuickNote(
            id: UUID(), content: "\n\n첫 줄\n  둘째 \n\n셋째",
            isPinned: false, createdAt: Date(), updatedAt: Date()
        )
        XCTAssertEqual(note.title, "첫 줄", "빈 줄은 건너뛴다")
        XCTAssertEqual(note.rest, "둘째 셋째", "나머지는 한 줄로 잇는다")

        let single = QuickNote(id: UUID(), content: "한 줄뿐", isPinned: false, createdAt: Date(), updatedAt: Date())
        XCTAssertNil(single.rest)

        XCTAssertEqual(NoteText.title(of: "   \n\n "), "제목 없음")
    }
}
