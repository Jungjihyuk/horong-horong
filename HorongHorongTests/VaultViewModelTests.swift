import XCTest
@testable import 호롱호롱

/// **디스크 없이** vault 화면의 규칙을 검사한다.
@MainActor
final class VaultViewModelTests: XCTestCase {
    private final class FakeRepository: VaultRepository {
        var scan = VaultScan(roots: [], wikiIndex: [:])
        var documents: [URL: String] = [:]
        var links: [String: URL] = [:]
        private(set) var scanCount = 0
        /// 본문 읽기를 붙잡아 둔다. «늦게 온 응답» 상황을 만들 때 쓴다.
        var documentDelay: Duration?

        func scan(kind: VaultKind, vault: URL, forceReload: Bool) async -> VaultScan {
            scanCount += 1
            return scan
        }

        func document(at url: URL) async -> String? {
            if let documentDelay { try? await Task.sleep(for: documentDelay) }
            return documents[url]
        }

        func resolveWikiLink(_ title: String, from current: URL?, in index: [String: [URL]]) -> URL? {
            links[title]
        }

        private(set) var deletedURLs: [URL] = []
        func delete(at url: URL, root: URL) async throws {
            deletedURLs.append(url)
            documents.removeValue(forKey: url)
        }
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func node(_ name: String, children: [VaultNode] = [], isDirectory: Bool = false) -> VaultNode {
        VaultNode(name: name, url: url("/vault/\(name)"), isDirectory: isDirectory, children: children)
    }

    private func make() -> (VaultViewModel, FakeRepository) {
        let repository = FakeRepository()
        return (VaultViewModel(kind: .knowledge, repository: repository), repository)
    }

    // MARK: - 검색 필터

    func testSearchKeepsMatchingLeaves() {
        let (viewModel, repository) = make()
        repository.scan = VaultScan(
            roots: [node("루트", children: [node("회고.md"), node("계획.md")], isDirectory: true)],
            wikiIndex: [:]
        )

        let expectation = expectation(description: "scan")
        Task { await viewModel.load(vault: url("/vault")); expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        viewModel.searchText = "회고"

        XCTAssertEqual(viewModel.filteredRoots.count, 1)
        XCTAssertEqual(viewModel.filteredRoots.first?.children.map(\.name), ["회고.md"])
    }

    /// 폴더 이름이 맞으면 그 아래는 통째로 남긴다 — 폴더로 찾는 사람이 있다.
    func testSearchMatchingFolderKeepsWholeSubtree() {
        let (viewModel, repository) = make()
        repository.scan = VaultScan(
            roots: [node("회고", children: [node("a.md"), node("b.md")], isDirectory: true)],
            wikiIndex: [:]
        )

        let expectation = expectation(description: "scan")
        Task { await viewModel.load(vault: url("/vault")); expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        viewModel.searchText = "회고"

        XCTAssertEqual(viewModel.filteredRoots.first?.children.count, 2)
    }

    func testEmptySearchReturnsEverything() {
        let (viewModel, repository) = make()
        repository.scan = VaultScan(roots: [node("a.md"), node("b.md")], wikiIndex: [:])

        let expectation = expectation(description: "scan")
        Task { await viewModel.load(vault: url("/vault")); expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        viewModel.searchText = "   "
        XCTAssertEqual(viewModel.filteredRoots.count, 2)
    }

    // MARK: - 문서 열기

    func testOpenLoadsMarkdown() async {
        let (viewModel, repository) = make()
        let target = url("/vault/노트.md")
        repository.documents[target] = "# 제목"

        await viewModel.open(target)

        XCTAssertEqual(viewModel.markdown, "# 제목")
        XCTAssertNil(viewModel.loadError)
    }

    func testUnreadableFileShowsError() async {
        let (viewModel, _) = make()

        await viewModel.open(url("/vault/없는파일.md"))

        XCTAssertEqual(viewModel.loadError, "파일을 읽지 못했습니다")
        XCTAssertEqual(viewModel.markdown, "")
    }

    /// md 가 아니면 읽지 않는다. 큰 이진 파일을 문자열로 읽으려 들면 안 된다.
    func testNonMarkdownIsNotRead() async {
        let (viewModel, repository) = make()
        let target = url("/vault/그림.png")
        repository.documents[target] = "읽으면 안 됨"

        await viewModel.open(target)

        XCTAssertEqual(viewModel.markdown, "")
        XCTAssertNil(viewModel.loadError)
    }

    /// **읽는 사이에 다른 문서를 고르면 늦게 온 결과를 버린다.**
    /// 안 버리면 방금 고른 문서 자리에 이전 문서 내용이 나타난다.
    func testLateResultIsDiscarded() async {
        let (viewModel, repository) = make()
        let slow = url("/vault/느린.md")
        let fast = url("/vault/빠른.md")
        repository.documents[slow] = "느린 본문"
        repository.documents[fast] = "빠른 본문"
        repository.documentDelay = .milliseconds(120)

        async let first: Void = viewModel.open(slow)
        try? await Task.sleep(for: .milliseconds(20))
        repository.documentDelay = nil
        await viewModel.open(fast)
        await first

        XCTAssertEqual(viewModel.selectedURL, fast)
        XCTAssertEqual(viewModel.markdown, "빠른 본문")
    }

    // MARK: - 위키 링크

    func testFollowWikiLinkOpensTarget() async {
        let (viewModel, repository) = make()
        let target = url("/vault/대상.md")
        repository.documents[target] = "대상 본문"
        repository.links["대상"] = target

        await viewModel.followWikiLink("대상")

        XCTAssertEqual(viewModel.selectedURL, target)
        XCTAssertEqual(viewModel.markdown, "대상 본문")
    }

    /// 가리키는 문서가 없으면 보고 있던 것을 그대로 둔다.
    func testUnresolvedWikiLinkKeepsCurrentDocument() async {
        let (viewModel, repository) = make()
        let current = url("/vault/현재.md")
        repository.documents[current] = "현재 본문"
        await viewModel.open(current)

        await viewModel.followWikiLink("없는제목")

        XCTAssertEqual(viewModel.selectedURL, current)
        XCTAssertEqual(viewModel.markdown, "현재 본문")
    }

    // MARK: - 문서 탭

    func testOpeningSecondDocumentKeepsFirstTab() async {
        let (viewModel, repository) = make()
        let first = url("/vault/첫.md"), second = url("/vault/둘.md")
        repository.documents[first] = "첫 본문"
        repository.documents[second] = "둘 본문"

        await viewModel.open(first)
        await viewModel.open(second)

        XCTAssertEqual(viewModel.openTabs, [first, second])
        XCTAssertEqual(viewModel.selectedURL, second)
        XCTAssertEqual(viewModel.markdown, "둘 본문")
    }

    func testOpeningSameDocumentTwiceKeepsOneTab() async {
        let (viewModel, repository) = make()
        let target = url("/vault/노트.md")
        repository.documents[target] = "본문"

        await viewModel.open(target)
        await viewModel.open(target)

        XCTAssertEqual(viewModel.openTabs, [target])
    }

    /// **이미 보고 있는 탭을 누르면 다시 읽지 않는다.** 다시 읽으면 편집기가
    /// 재초기화되어 커서와 undo 가 날아간다.
    func testSelectingActiveTabDoesNotReloadDocument() async {
        let (viewModel, repository) = make()
        let target = url("/vault/노트.md")
        repository.documents[target] = "본문"
        await viewModel.open(target)
        let version = viewModel.documentVersion

        await viewModel.select(target)

        XCTAssertEqual(viewModel.documentVersion, version)
    }

    func testSelectingOtherTabSwitchesDocument() async {
        let (viewModel, repository) = make()
        let first = url("/vault/첫.md"), second = url("/vault/둘.md")
        repository.documents[first] = "첫 본문"
        repository.documents[second] = "둘 본문"
        await viewModel.open(first)
        await viewModel.open(second)

        await viewModel.select(first)

        XCTAssertEqual(viewModel.selectedURL, first)
        XCTAssertEqual(viewModel.markdown, "첫 본문")
        XCTAssertEqual(viewModel.openTabs, [first, second])
    }

    /// 보고 있던 탭을 닫으면 오른쪽 탭으로 옮긴다.
    func testClosingActiveTabActivatesNextTab() async {
        let (viewModel, repository) = make()
        let first = url("/vault/첫.md"), second = url("/vault/둘.md"), third = url("/vault/셋.md")
        for (target, text) in [(first, "첫 본문"), (second, "둘 본문"), (third, "셋 본문")] {
            repository.documents[target] = text
        }
        await viewModel.open(first)
        await viewModel.open(second)
        await viewModel.open(third)
        await viewModel.select(first)

        await viewModel.close(first)

        XCTAssertEqual(viewModel.openTabs, [second, third])
        XCTAssertEqual(viewModel.selectedURL, second)
        XCTAssertEqual(viewModel.markdown, "둘 본문")
    }

    func testClosingInactiveTabKeepsCurrentDocument() async {
        let (viewModel, repository) = make()
        let first = url("/vault/첫.md"), second = url("/vault/둘.md")
        repository.documents[first] = "첫 본문"
        repository.documents[second] = "둘 본문"
        await viewModel.open(first)
        await viewModel.open(second)
        let version = viewModel.documentVersion

        await viewModel.close(first)

        XCTAssertEqual(viewModel.openTabs, [second])
        XCTAssertEqual(viewModel.selectedURL, second)
        XCTAssertEqual(viewModel.documentVersion, version)
    }

    func testClosingLastTabClearsDocument() async {
        let (viewModel, repository) = make()
        let target = url("/vault/노트.md")
        repository.documents[target] = "본문"
        await viewModel.open(target)

        await viewModel.close(target)

        XCTAssertTrue(viewModel.openTabs.isEmpty)
        XCTAssertNil(viewModel.selectedURL)
        XCTAssertEqual(viewModel.markdown, "")
    }

    /// 폴더를 지우면 그 아래 열려 있던 탭도 함께 닫힌다.
    func testDeleteClosesTabsUnderDeletedPath() async {
        let (viewModel, repository) = make()
        let outside = url("/vault/바깥.md"), inside = url("/vault/폴더/안.md")
        repository.documents[outside] = "바깥 본문"
        repository.documents[inside] = "안 본문"
        await viewModel.load(vault: url("/vault"))
        await viewModel.open(outside)
        await viewModel.open(inside)

        await viewModel.delete(at: url("/vault/폴더"))

        XCTAssertEqual(viewModel.openTabs, [outside])
        XCTAssertEqual(viewModel.selectedURL, outside)
        XCTAssertEqual(viewModel.markdown, "바깥 본문")
    }

    func testDeleteClearsSelectedDocumentWhenDeleted() async {
        let (viewModel, repository) = make()
        let target = url("/vault/노트.md")
        repository.documents[target] = "본문"
        await viewModel.load(vault: url("/vault"))
        await viewModel.open(target)
        XCTAssertEqual(viewModel.selectedURL, target)

        await viewModel.delete(at: target)

        XCTAssertNil(viewModel.selectedURL)
        XCTAssertEqual(viewModel.markdown, "")
        XCTAssertEqual(repository.deletedURLs, [target])
    }
}
