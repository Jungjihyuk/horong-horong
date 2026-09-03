import XCTest
@testable import 호롱호롱

/// **화면을 띄우지 않고** 목록 로직을 검사한다. 계층을 나눈 이유 중 하나가 이것이다 —
/// `@Query` 를 쓰던 때는 이 동작을 확인하려면 앱을 실행해야 했다.
@MainActor
final class ReferencesViewModelTests: XCTestCase {
    /// 저장소를 흉내 내는 가짜. SwiftData 도 파일도 쓰지 않는다.
    private final class FakeRepository: ReferenceRepository {
        var items: [Reference] = []
        private(set) var fetchCount = 0

        func references(matching query: String, limit: Int) throws -> [Reference] {
            fetchCount += 1
            let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
            let filtered = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? sorted
                : sorted.filter { $0.content.localizedCaseInsensitiveContains(query) }
            return Array(filtered.prefix(limit))
        }

        func reference(id: UUID) throws -> Reference? { items.first { $0.id == id } }

        @discardableResult
        func add(content: String) throws -> Reference {
            let made = Reference(id: UUID(), content: content, updatedAt: Date())
            items.append(made)
            return made
        }

        func updateContent(id: UUID, content: String) throws {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index] = Reference(id: id, content: content, updatedAt: Date())
        }

        func delete(id: UUID) throws { items.removeAll { $0.id == id } }
    }

    private func make(count: Int) -> (ReferencesViewModel, FakeRepository) {
        let repository = FakeRepository()
        let base = Date()
        repository.items = (0..<count).map {
            Reference(id: UUID(), content: "참고 \($0)", updatedAt: base.addingTimeInterval(Double($0)))
        }
        return (ReferencesViewModel(repository: repository), repository)
    }

    /// 처음에는 한 쪽(50건)만 가져온다. 전량 조회를 실수로 하지 않는지 본다.
    func testLoadsFirstPageOnly() {
        let (viewModel, _) = make(count: 130)
        viewModel.reload()

        XCTAssertEqual(viewModel.references.count, 50)
        XCTAssertTrue(viewModel.canLoadMore)
    }

    func testLoadMoreGrowsPage() {
        let (viewModel, _) = make(count: 130)
        viewModel.reload()
        viewModel.loadMore()

        XCTAssertEqual(viewModel.references.count, 100)
        XCTAssertTrue(viewModel.canLoadMore)

        viewModel.loadMore()
        XCTAssertEqual(viewModel.references.count, 130)
        XCTAssertFalse(viewModel.canLoadMore, "더 없으면 더 청하지 않는다")
    }

    /// 항목 수가 딱 한 쪽이면 «더 있음» 으로 오판하면 안 된다.
    func testExactPageSizeDoesNotOfferMore() {
        let (viewModel, _) = make(count: 50)
        viewModel.reload()

        XCTAssertEqual(viewModel.references.count, 50)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    /// 검색어를 바꾸면 자동으로 다시 불러온다.
    func testSearchTextTriggersReload() {
        let (viewModel, repository) = make(count: 10)
        viewModel.reload()
        let before = repository.fetchCount

        viewModel.searchText = "참고 3"

        XCTAssertGreaterThan(repository.fetchCount, before)
        XCTAssertEqual(viewModel.references.count, 1)
    }

    /// **결정 ①의 검증** — 추가하면 목록이 스스로 갱신된다(`@Query` 없이).
    func testAddRefreshesListAndSelects() {
        let (viewModel, _) = make(count: 3)
        viewModel.reload()

        viewModel.newContent = "https://example.com"
        viewModel.add()

        XCTAssertEqual(viewModel.references.count, 4)
        XCTAssertEqual(viewModel.selected?.content, "https://example.com")
        XCTAssertEqual(viewModel.newContent, "", "입력칸은 비운다")
    }

    func testDeleteRemovesAndMovesSelection() {
        let (viewModel, _) = make(count: 3)
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.references.first)

        viewModel.delete(target.id)

        XCTAssertEqual(viewModel.references.count, 2)
        XCTAssertNotEqual(viewModel.selected?.id, target.id)
        XCTAssertNotNil(viewModel.selected, "남은 것이 있으면 첫 항목을 고른다")
    }

    func testDeletingLastLeavesNoSelection() {
        let (viewModel, _) = make(count: 1)
        viewModel.reload()
        let only = try! XCTUnwrap(viewModel.references.first)

        viewModel.delete(only.id)

        XCTAssertTrue(viewModel.references.isEmpty)
        XCTAssertNil(viewModel.selected)
        XCTAssertEqual(viewModel.draft, "")
    }

    /// 빈 입력은 무시한다.
    func testBlankContentIsNotAdded() {
        let (viewModel, _) = make(count: 2)
        viewModel.reload()

        viewModel.newContent = "   \n  "
        viewModel.add()

        XCTAssertEqual(viewModel.references.count, 2)
    }

    /// Entity 가 링크를 알아본다.
    func testEntityDerivesTitleAndLink() {
        let link = Reference(id: UUID(), content: "https://example.com/a\n메모", updatedAt: Date())
        XCTAssertEqual(link.title, "https://example.com/a")
        XCTAssertTrue(link.isLink)
        XCTAssertEqual(link.linkURL?.host(), "example.com")

        let note = Reference(id: UUID(), content: "\n\n그냥 쪽지", updatedAt: Date())
        XCTAssertEqual(note.title, "그냥 쪽지", "빈 줄은 건너뛴다")
        XCTAssertFalse(note.isLink)
    }
}
