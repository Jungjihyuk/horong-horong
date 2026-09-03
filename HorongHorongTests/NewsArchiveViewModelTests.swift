import XCTest
@testable import 호롱호롱

/// 보관함은 **디스크가 근거**라 임시 폴더를 만들어 검사한다.
/// 덕분에 폴더 훑기(`NewsReportArchiveStore`)까지 함께 확인된다 — 그동안 테스트가 없던 곳이다.
@MainActor
final class NewsArchiveViewModelTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("news-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metaDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        base = nil
    }

    private var reportDirectory: URL {
        base.appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
    }

    private var metaDirectory: URL {
        base.appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("meta", isDirectory: true)
    }

    private func write(
        name: String,
        markdown: String,
        jobId: String,
        topTitle: String,
        keywords: [String] = []
    ) throws {
        try markdown.write(
            to: reportDirectory.appendingPathComponent("\(name).md"),
            atomically: true,
            encoding: .utf8
        )
        let meta: [String: Any] = [
            "jobId": jobId,
            "reportDate": name,
            "itemCount": 2,
            "interestKeywords": keywords,
            "topItems": [["title": topTitle]]
        ]
        try JSONSerialization.data(withJSONObject: meta).write(
            to: metaDirectory.appendingPathComponent("\(name).meta.json")
        )
    }

    private func loaded() throws -> NewsArchiveViewModel {
        let viewModel = NewsArchiveViewModel()
        viewModel.reload(dataBasePath: base.path)
        return viewModel
    }

    // MARK: - 훑기

    func testLoadsReportsNewestFirst() throws {
        try write(name: "2026-09-01", markdown: "# 어제", jobId: "job-1", topTitle: "어제 리포트")
        try write(name: "2026-09-03", markdown: "# 오늘", jobId: "job-2", topTitle: "오늘 리포트")

        let viewModel = try loaded()

        XCTAssertEqual(viewModel.entries.map(\.topTitle), ["오늘 리포트", "어제 리포트"])
    }

    /// md 가 아닌 파일은 리포트가 아니다.
    func testNonMarkdownFilesAreIgnored() throws {
        try write(name: "2026-09-03", markdown: "# 오늘", jobId: "job-1", topTitle: "오늘")
        try "noise".write(
            to: reportDirectory.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(try loaded().entries.count, 1)
    }

    /// meta 가 없으면 markdown 의 첫 `# ` 줄을 제목으로 쓴다.
    func testFallsBackToMarkdownTitleWithoutMeta() throws {
        try "# 메타 없는 리포트\n본문".write(
            to: reportDirectory.appendingPathComponent("2026-09-03.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(try loaded().entries.first?.topTitle, "메타 없는 리포트")
    }

    // MARK: - 검색

    /// **본문까지 뒤진다.** 제목에 없는 낱말로도 찾을 수 있어야 한다.
    func testSearchMatchesBodyText() throws {
        try write(name: "2026-09-01", markdown: "# 하나\n트랜스포머 이야기", jobId: "a", topTitle: "하나")
        try write(name: "2026-09-02", markdown: "# 둘\n날씨 이야기", jobId: "b", topTitle: "둘")

        let viewModel = try loaded()
        viewModel.searchText = "트랜스포머"

        XCTAssertEqual(viewModel.visibleEntries.map(\.topTitle), ["하나"])
    }

    func testSearchMatchesKeywords() throws {
        try write(name: "2026-09-01", markdown: "# 하나\n본문", jobId: "a", topTitle: "하나", keywords: ["로보틱스"])
        try write(name: "2026-09-02", markdown: "# 둘\n본문", jobId: "b", topTitle: "둘")

        let viewModel = try loaded()
        viewModel.searchText = "로보틱스"

        XCTAssertEqual(viewModel.visibleEntries.map(\.topTitle), ["하나"])
    }

    func testEmptySearchShowsEverything() throws {
        try write(name: "2026-09-01", markdown: "# 하나", jobId: "a", topTitle: "하나")
        try write(name: "2026-09-02", markdown: "# 둘", jobId: "b", topTitle: "둘")

        let viewModel = try loaded()
        viewModel.searchText = "   "

        XCTAssertEqual(viewModel.visibleEntries.count, 2)
    }

    // MARK: - 선택

    func testSelectionFollowsWhenFilteredOut() throws {
        try write(name: "2026-09-01", markdown: "# 하나\n사과", jobId: "a", topTitle: "하나")
        try write(name: "2026-09-02", markdown: "# 둘\n바나나", jobId: "b", topTitle: "둘")

        let viewModel = try loaded()
        let apple = try XCTUnwrap(viewModel.entries.first { $0.topTitle == "하나" })
        viewModel.select(apple.id)

        viewModel.searchText = "바나나"

        XCTAssertNotEqual(viewModel.selectedEntryID, apple.id)
        XCTAssertEqual(viewModel.selectedEntry?.topTitle, "둘")
    }

    /// 다른 창이 「이 리포트를 열어라」고 하면 `jobId` 로 찾는다.
    func testSelectionRequestOpensRequestedReport() throws {
        try write(name: "2026-09-01", markdown: "# 하나", jobId: "job-a", topTitle: "하나")
        try write(name: "2026-09-02", markdown: "# 둘", jobId: "job-b", topTitle: "둘")

        let viewModel = try loaded()
        viewModel.applySelectionRequest(reportID: "job-a")

        XCTAssertEqual(viewModel.selectedEntry?.topTitle, "하나")
    }

    /// 요청한 것이 없으면 첫 항목으로 떨어진다 — 빈 화면이 남지 않게.
    func testUnknownSelectionRequestFallsBackToFirst() throws {
        try write(name: "2026-09-02", markdown: "# 둘", jobId: "job-b", topTitle: "둘")

        let viewModel = try loaded()
        viewModel.applySelectionRequest(reportID: "없는-id")

        XCTAssertEqual(viewModel.selectedEntry?.topTitle, "둘")
    }

    func testEmptyDirectoryHasNoSelection() throws {
        let viewModel = try loaded()

        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertNil(viewModel.selectedEntry)
    }
}
