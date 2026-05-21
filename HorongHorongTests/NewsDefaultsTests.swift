import XCTest
@testable import 호롱호롱

final class NewsDefaultsTests: XCTestCase {
    func testDefaultNewsSourcesUsePublicFriendlyValues() {
        let sources = NewsSource.defaultSources

        let youtube = sources.first { $0.type == "youtube" }
        XCTAssertEqual(youtube?.enabled, true)
        XCTAssertEqual(youtube?.channelId, "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertNil(youtube?.playlists)

        let googleNews = sources.first { $0.type == "google_news" }
        XCTAssertEqual(googleNews?.enabled, true)
        XCTAssertEqual(googleNews?.keywords, ["AI", "개발", "생산성", "자동화"])

        let yozm = sources.first { $0.type == "yozm_it" }
        XCTAssertEqual(yozm?.enabled, true)
        XCTAssertEqual(yozm?.keywords, ["개발", "생산성", "AI", "자동화"])

        let linkedIn = sources.first { $0.type == "linkedin" }
        XCTAssertEqual(linkedIn?.enabled, false)
    }

    func testNewsRunnerPathUsesBundleResourceBeforeRepositorySource() throws {
        let bundleResourceURL = temporaryDirectory().appendingPathComponent("Resources", isDirectory: true)
        let repositoryRootURL = temporaryDirectory().appendingPathComponent("Repository", isDirectory: true)
        let bundleRunnerURL = bundleResourceURL
            .appendingPathComponent("news_report", isDirectory: true)
            .appendingPathComponent("runner.py", isDirectory: false)
        let repositoryRunnerURL = repositoryRootURL
            .appendingPathComponent("Agents", isDirectory: true)
            .appendingPathComponent("news_report", isDirectory: true)
            .appendingPathComponent("runner.py", isDirectory: false)
        try writeFile(at: bundleRunnerURL)
        try writeFile(at: repositoryRunnerURL)

        XCTAssertEqual(
            Constants.newsRunnerPath(
                bundleResourceURL: bundleResourceURL,
                repositoryRootPath: repositoryRootURL.path
            ),
            bundleRunnerURL.path
        )
    }

    func testNewsRunnerPathFallsBackToRepositorySource() throws {
        let repositoryRootURL = temporaryDirectory().appendingPathComponent("Repository", isDirectory: true)
        let repositoryRunnerURL = repositoryRootURL
            .appendingPathComponent("Agents", isDirectory: true)
            .appendingPathComponent("news_report", isDirectory: true)
            .appendingPathComponent("runner.py", isDirectory: false)
        try writeFile(at: repositoryRunnerURL)

        XCTAssertEqual(
            Constants.newsRunnerPath(
                bundleResourceURL: nil,
                repositoryRootPath: repositoryRootURL.path
            ),
            repositoryRunnerURL.path
        )
    }

    func testNewsDataBasePathUsesApplicationSupportWhenRepositoryIsUnavailable() {
        let applicationSupportDirectory = temporaryDirectory()

        XCTAssertEqual(
            Constants.newsDataBasePath(
                repositoryRootPath: nil,
                applicationSupportDirectory: applicationSupportDirectory
            ),
            applicationSupportDirectory
                .appendingPathComponent("HorongHorong", isDirectory: true)
                .appendingPathComponent("news_report", isDirectory: true)
                .path
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/usr/bin/env python3\n".write(to: url, atomically: true, encoding: .utf8)
    }
}
