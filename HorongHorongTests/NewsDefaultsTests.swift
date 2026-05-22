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

    func testNewsProviderCLIResolverMapsSupportedProviders() {
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "claude"), "claude")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "codex"), "codex")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "gemini"), "gemini")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "opencode"), "opencode")
        XCTAssertNil(NewsProviderCLIResolver.command(for: "unknown"))
    }

    func testNewsProviderCLIResolverUsesLoginShellWhenCurrentPathMissesProvider() throws {
        var calls: [(executable: String, arguments: [String])] = []
        let resolver = NewsProviderCLIResolver(
            environment: [
                "PATH": "/usr/bin:/bin",
                "SHELL": "/mock/zsh",
            ],
            commandRunner: { executable, arguments, _ in
                calls.append((executable, arguments))
                if executable == "/mock/zsh" {
                    return "/Users/example/.volta/bin/codex\n"
                }
                return nil
            },
            isExecutable: { path in
                path == "/Users/example/.volta/bin/codex"
            }
        )

        let resolution = try XCTUnwrap(try? resolver.resolve(provider: "codex").get())

        XCTAssertEqual(resolution.executablePath, "/Users/example/.volta/bin/codex")
        XCTAssertEqual(
            resolution.environment["PATH"],
            "/Users/example/.volta/bin:/usr/bin:/bin"
        )
        XCTAssertEqual(calls.map(\.executable), ["/bin/sh", "/mock/zsh"])
    }

    func testNewsProviderCLIResolverUsesUserShellWhenEnvironmentShellIsMissing() throws {
        var calls: [(executable: String, arguments: [String])] = []
        let resolver = NewsProviderCLIResolver(
            environment: [
                "PATH": "/usr/bin:/bin",
            ],
            commandRunner: { executable, arguments, _ in
                calls.append((executable, arguments))
                if executable == "/mock/fish" {
                    return "/Users/example/.local/bin/claude\n"
                }
                return nil
            },
            isExecutable: { path in
                path == "/Users/example/.local/bin/claude"
            },
            userShellProvider: {
                "/mock/fish"
            }
        )

        let resolution = try XCTUnwrap(try? resolver.resolve(provider: "claude").get())

        XCTAssertEqual(resolution.executablePath, "/Users/example/.local/bin/claude")
        XCTAssertEqual(
            resolution.environment["PATH"],
            "/Users/example/.local/bin:/usr/bin:/bin"
        )
        XCTAssertEqual(calls.map(\.executable), ["/bin/sh", "/mock/fish"])
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
