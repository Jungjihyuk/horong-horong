import XCTest
@testable import 호롱호롱

/// 저장소도 화면도 없이 References 화면의 규칙을 검사한다.
@MainActor
final class ReferencesViewModelTests: XCTestCase {
    /// 저장소를 흉내 내는 가짜. SwiftData 도 파일도 쓰지 않는다.
    private final class FakeRepository: ReferenceRepository {
        var items: [ReferenceItem] = []
        private(set) var fetchCount = 0
        private(set) var lastKind: ReferenceKind??

        func references(matching query: String, kind: ReferenceKind?, limit: Int) throws -> [ReferenceItem] {
            fetchCount += 1
            lastKind = kind
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return items
                .sorted { $0.updatedAt > $1.updatedAt }
                .filter { kind == nil || $0.kind == kind }
                .filter { trimmed.isEmpty || Self.matches($0, trimmed) }
                .prefix(limit)
                .map { $0 }
        }

        func reference(id: UUID) throws -> ReferenceItem? { items.first { $0.id == id } }

        @discardableResult
        func add(kind: ReferenceKind) throws -> ReferenceItem {
            let made = ReferenceItem(id: UUID(), kind: kind, title: "", updatedAt: Date())
            items.append(made)
            return made
        }

        @discardableResult
        func update(id: UUID, _ change: ReferenceChange) throws -> ReferenceItem? {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
            let old = items[index]
            let updated = ReferenceItem(
                id: old.id,
                kind: old.kind,
                title: change.title ?? old.title,
                url: change.url ?? old.url,
                body: change.body ?? old.body,
                color: change.color ?? old.color,
                isWidget: change.isWidget ?? old.isWidget,
                widgetPosition: change.widgetPosition ?? old.widgetPosition,
                updatedAt: Date()
            )
            items[index] = updated
            return updated
        }

        func delete(id: UUID) throws { items.removeAll { $0.id == id } }

        func widgetNotes() throws -> [ReferenceItem] {
            items.filter { $0.kind == .note && $0.isWidget }
        }

        private static func matches(_ item: ReferenceItem, _ query: String) -> Bool {
            [item.title, item.url ?? "", item.body]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func make() -> (ReferencesViewModel, FakeRepository) {
        let repository = FakeRepository()
        return (ReferencesViewModel(repository: repository), repository)
    }

    private func seed(_ repository: FakeRepository, links: Int, notes: Int) {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var offset = 0.0
        for index in 0..<links {
            repository.items.append(ReferenceItem(
                id: UUID(), kind: .link, title: "링크 \(index)",
                url: "https://example.com/\(index)", updatedAt: base.addingTimeInterval(offset)
            ))
            offset += 1
        }
        for index in 0..<notes {
            repository.items.append(ReferenceItem(
                id: UUID(), kind: .note, title: "쪽지 \(index)",
                body: "본문 \(index)", updatedAt: base.addingTimeInterval(offset)
            ))
            offset += 1
        }
    }

    // MARK: - 갈래 나누기

    /// 전체 → 링크 → 쪽지 로 바꾸면 그때마다 저장소에 다시 묻는다.
    func testModeFiltersThroughTheRepository() {
        let (viewModel, repository) = make()
        seed(repository, links: 3, notes: 2)
        viewModel.reload()
        XCTAssertEqual(viewModel.references.count, 5)

        viewModel.mode = .link
        XCTAssertEqual(repository.lastKind, .link, "거르는 일은 저장소가 한다")
        XCTAssertEqual(viewModel.references.count, 3)
        XCTAssertTrue(viewModel.references.allSatisfy { $0.kind == .link })

        viewModel.mode = .note
        XCTAssertEqual(viewModel.references.count, 2)

        viewModel.mode = nil
        XCTAssertEqual(viewModel.references.count, 5)
    }

    /// 같은 모드를 다시 넣으면 다시 읽지 않는다.
    func testSettingTheSameModeDoesNotRefetch() {
        let (viewModel, repository) = make()
        viewModel.mode = .link
        let before = repository.fetchCount

        viewModel.mode = .link

        XCTAssertEqual(repository.fetchCount, before)
    }

    /// **거르기가 페이징보다 먼저다.** 화면에서 걸렀다면 링크 60개 중 50개만 받아
    /// 그중 링크를 세느라 «더 있다» 를 놓쳤을 것이다.
    func testPagingCountsFilteredItems() {
        let (viewModel, repository) = make()
        seed(repository, links: 60, notes: 60)
        viewModel.mode = .link

        XCTAssertEqual(viewModel.references.count, 50)
        XCTAssertTrue(viewModel.canLoadMore)

        viewModel.loadMore()

        XCTAssertEqual(viewModel.references.count, 60)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testExactPageSizeDoesNotOfferMore() {
        let (viewModel, repository) = make()
        seed(repository, links: 50, notes: 0)
        viewModel.reload()

        XCTAssertEqual(viewModel.references.count, 50)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testSearchTextTriggersReload() {
        let (viewModel, repository) = make()
        seed(repository, links: 3, notes: 0)
        viewModel.reload()
        let before = repository.fetchCount

        viewModel.searchText = "링크 1"

        XCTAssertGreaterThan(repository.fetchCount, before)
        XCTAssertEqual(viewModel.references.count, 1)
    }

    // MARK: - 만들기·고치기

    func testAddCreatesTheRequestedKindAndSelectsIt() {
        let (viewModel, _) = make()
        viewModel.reload()

        viewModel.add(kind: .note)

        XCTAssertEqual(viewModel.selected?.kind, .note)
        XCTAssertEqual(viewModel.references.count, 1)
    }

    /// 링크만 보는 중에 쪽지를 만들면 만든 것이 안 보인다 — 모드를 따라 옮겨 준다.
    func testAddSwitchesModeSoTheNewItemIsVisible() {
        let (viewModel, repository) = make()
        seed(repository, links: 2, notes: 0)
        viewModel.mode = .link

        viewModel.add(kind: .note)

        XCTAssertEqual(viewModel.mode, .note)
        XCTAssertTrue(viewModel.references.contains { $0.id == viewModel.selected?.id })
    }

    func testDraftsPersistTitleAndUrlForLinks() {
        let (viewModel, repository) = make()
        viewModel.add(kind: .link)
        let id = try? XCTUnwrap(viewModel.selected?.id)

        viewModel.titleDraft = "에이전트 논문"
        viewModel.urlDraft = "https://arxiv.org/abs/1"
        viewModel.flush()

        let saved = repository.items.first { $0.id == id }
        XCTAssertEqual(saved?.title, "에이전트 논문")
        XCTAssertEqual(saved?.url, "https://arxiv.org/abs/1")
    }

    /// 쪽지에는 주소를 쓰지 않는다 — 링크 칸의 잔상이 넘어오면 안 된다.
    func testNoteDraftsOnlyPersistBody() {
        let (viewModel, repository) = make()
        viewModel.add(kind: .note)
        let id = try? XCTUnwrap(viewModel.selected?.id)

        viewModel.bodyDraft = "면수를 남기는 게 전부"
        viewModel.urlDraft = "https://버려질주소"
        viewModel.flush()

        let saved = repository.items.first { $0.id == id }
        XCTAssertEqual(saved?.body, "면수를 남기는 게 전부")
        XCTAssertNil(saved?.url)
    }

    func testSetColorAndWidgetPersist() {
        let (viewModel, repository) = make()
        viewModel.add(kind: .note)
        let id = try? XCTUnwrap(viewModel.selected?.id)

        viewModel.setColor(.blue)
        viewModel.setWidget(true)

        let saved = repository.items.first { $0.id == id }
        XCTAssertEqual(saved?.color, .blue)
        XCTAssertEqual(saved?.isWidget, true)
        XCTAssertEqual(try? repository.widgetNotes().count, 1)
    }

    func testDeleteRemovesAndMovesSelection() {
        let (viewModel, repository) = make()
        seed(repository, links: 3, notes: 0)
        viewModel.reload()
        let first = try? XCTUnwrap(viewModel.selected?.id)

        viewModel.delete(first ?? UUID())

        XCTAssertEqual(viewModel.references.count, 2)
        XCTAssertNotEqual(viewModel.selected?.id, first)
        XCTAssertNotNil(viewModel.selected)
    }

    func testDeletingLastLeavesNoSelection() {
        let (viewModel, _) = make()
        viewModel.add(kind: .link)
        let id = try? XCTUnwrap(viewModel.selected?.id)

        viewModel.delete(id ?? UUID())

        XCTAssertNil(viewModel.selected)
        XCTAssertEqual(viewModel.titleDraft, "")
        XCTAssertEqual(viewModel.bodyDraft, "")
    }

    // MARK: - 값 타입

    /// 스킴을 빠뜨린 주소도 열 수 있어야 한다.
    func testLinkURLAcceptsSchemelessInput() {
        let bare = ReferenceItem(id: UUID(), kind: .link, title: "", url: "www.figma.com", updatedAt: Date())
        XCTAssertEqual(bare.linkURL?.host(), "www.figma.com")
        XCTAssertEqual(bare.host, "figma.com", "www. 는 떼고 보여 준다")

        let full = ReferenceItem(id: UUID(), kind: .link, title: "", url: "https://arxiv.org/a", updatedAt: Date())
        XCTAssertEqual(full.host, "arxiv.org")
    }

    /// 쪽지에는 주소가 있어도 링크로 열지 않는다.
    func testNoteNeverProducesALinkURL() {
        let note = ReferenceItem(id: UUID(), kind: .note, title: "", url: "https://x.com", body: "본문", updatedAt: Date())
        XCTAssertNil(note.linkURL)
        XCTAssertNil(note.host)
    }

    func testDisplayTitleFallsBackPerKind() {
        XCTAssertEqual(ReferenceItem(id: UUID(), kind: .link, title: "  ", updatedAt: Date()).displayTitle, "제목 없음")
        XCTAssertEqual(ReferenceItem(id: UUID(), kind: .note, title: "", updatedAt: Date()).displayTitle, "쪽지")
    }

    func testColorFallsBackWhenStoredValueIsUnknown() {
        XCTAssertEqual(ReferenceNoteColor.resolve("보라"), .yellow)
        XCTAssertEqual(ReferenceNoteColor.resolve(nil), .yellow)
        XCTAssertEqual(ReferenceNoteColor.resolve("blue"), .blue)
    }
}
