import XCTest
@testable import 호롱호롱

final class NewsDefaultsTests: XCTestCase {
    func testNewsReportMarkdownParserKeepsReportStructure() {
        let markdown = """
        # 뉴스 큐레이션 리포트 - 2026-08-03
        생성일: 2026-08-03 20:00
        ## AI 에이전트
        🔑 키워드: agent, 자동화
        ### 1. [AI 뉴스](https://example.com)
        > 중요도: 90/100 | 관련성: 95/100 | google_news
        **AI 에이전트 도입이 늘고 있다.**
        - 기업 도입 사례 증가
        1. AI 뉴스 읽기 및 정리
        """

        XCTAssertEqual(
            NewsReportMarkdownParser.parse(markdown),
            [
                .title("뉴스 큐레이션 리포트 - 2026-08-03"),
                .metadata("생성일: 2026-08-03 20:00"),
                .heading(level: 2, text: "AI 에이전트"),
                .insight("🔑 키워드: agent, 자동화"),
                .heading(level: 3, text: "1. [AI 뉴스](https://example.com)"),
                .quote("중요도: 90/100 | 관련성: 95/100 | google_news"),
                .callout("**AI 에이전트 도입이 늘고 있다.**"),
                .bullet("기업 도입 사례 증가"),
                .numbered(number: "1", text: "AI 뉴스 읽기 및 정리"),
            ]
        )
    }

    func testNewsReportDocumentSearchesTitleFilenameKeywordsAndBody() {
        let document = NewsReportArchiveDocument(
            markdown: "SwiftUI 뉴스 본문",
            interestKeywords: ["AI agent", "생산성"],
            fileSize: 1_024,
            errorMessage: nil
        )

        XCTAssertTrue(document.matches(query: "주간", title: "주간 리포트", filename: "report.md"))
        XCTAssertTrue(document.matches(query: "report", title: "주간 리포트", filename: "report.md"))
        XCTAssertTrue(document.matches(query: "agent", title: "주간 리포트", filename: "report.md"))
        XCTAssertTrue(document.matches(query: "swiftui", title: "주간 리포트", filename: "report.md"))
        XCTAssertFalse(document.matches(query: "없는 검색어", title: "주간 리포트", filename: "report.md"))
    }

    func testNewsReportArchiveStoreLoadsConfiguredDirectoryInsteadOfStoredAbsolutePath() throws {
        let dataBaseURL = temporaryDirectory().appendingPathComponent("Configured Reports", isDirectory: true)
        let reportDirectory = dataBaseURL
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
        let metaDirectory = dataBaseURL
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("meta", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metaDirectory, withIntermediateDirectories: true)

        let reportURL = reportDirectory.appendingPathComponent("2026-07-22-0329.md")
        let metaURL = metaDirectory.appendingPathComponent("2026-07-22-0329.meta.json")
        try "# 설정 폴더의 뉴스 리포트\n".write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        {
          "jobId": "2026-07-22-032401-KST",
          "reportDate": "2026-07-22",
          "itemCount": 19,
          "interestKeywords": ["AI", "개발"],
          "topItems": [{"title": "설정 폴더의 첫 뉴스"}]
        }
        """.write(to: metaURL, atomically: true, encoding: .utf8)

        let entries = NewsReportArchiveStore.loadEntries(dataBasePath: dataBaseURL.path)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entry.reportURL.resolvingSymlinksInPath().path,
            reportURL.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            entry.metaURL.resolvingSymlinksInPath().path,
            metaURL.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(entry.jobId, "2026-07-22-032401-KST")
        XCTAssertEqual(entry.itemCount, 19)
        XCTAssertEqual(entry.topTitle, "설정 폴더의 첫 뉴스")

        let configuredURL = NewsReportArchiveStore.configuredReportURL(
            reportPath: "/old/location/data/reports/2026-07-22-0329.md",
            dataBasePath: dataBaseURL.path
        )
        XCTAssertEqual(
            configuredURL.resolvingSymlinksInPath().path,
            reportURL.resolvingSymlinksInPath().path
        )
    }

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

    func testNewsRunnerPathUsesRepositorySourceBeforeBundleResource() throws {
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
            repositoryRunnerURL.path
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
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "codex"), "codex")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "claude"), "claude")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "gemini"), "gemini")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "opencode"), "opencode")
        XCTAssertEqual(NewsProviderCLIResolver.command(for: "antigravity"), "agy")
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

    func testNewsProviderCLIResolverParsesPathFromNoisyShellOutput() {
        let output = """
        mkdir: /Users/example/.cache/oh-my-zsh: Operation not permitted
        \u{1B}]12;#ff79c6\u{07}/Users/example/.nvm/versions/node/v24.13.0/bin/claude\u{1B}[0m
        """

        XCTAssertEqual(
            NewsProviderCLIResolver.executablePath(for: "claude", in: output),
            "/Users/example/.nvm/versions/node/v24.13.0/bin/claude"
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
