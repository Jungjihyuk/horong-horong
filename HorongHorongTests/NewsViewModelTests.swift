import XCTest
@testable import 호롱호롱

/// **저장소도 파이프라인도 없이** 뉴스 화면의 규칙을 검사한다.
@MainActor
final class NewsViewModelTests: XCTestCase {
    private final class FakeRepository: NewsRepository {
        var reports: [NewsReport] = []
        var jobs: [NewsJobRun] = []
        private(set) var reportFetchCount = 0

        func recentReports(limit: Int) throws -> [NewsReport] {
            reportFetchCount += 1
            return Array(reports.prefix(limit))
        }

        func recentJobs(limit: Int) throws -> [NewsJobRun] { Array(jobs.prefix(limit)) }
        func reportIdentifiers() throws -> [String] { reports.map(\.jobId) }
    }

    private final class FakePipeline: NewsPipelineGateway {
        private(set) var launchCount = 0
        func launch() { launchCount += 1 }
    }

    /// 특정 경로만 «있다» 고 답하는 파일 시스템.
    private final class StubFileManager: FileManager {
        var existingPaths: Set<String> = []
        override func fileExists(atPath path: String) -> Bool { existingPaths.contains(path) }
    }

    private func report(_ jobId: String, fileName: String) -> NewsReport {
        NewsReport(
            jobId: jobId,
            reportDate: Date(),
            reportPath: "/anywhere/\(fileName)",
            metaPath: "/anywhere/\(fileName).meta.json",
            topTitle: "제목 \(jobId)",
            itemCount: 3,
            createdAt: Date()
        )
    }

    private func job(provider: String, usage: NewsJobUsage?) -> NewsJobRun {
        NewsJobRun(
            jobId: UUID().uuidString,
            status: "success",
            provider: provider,
            requestedAt: Date(),
            startedAt: nil,
            endedAt: nil,
            errorCode: nil,
            errorMessage: nil,
            logPath: nil,
            usage: usage
        )
    }

    private func usage(calls: Int) -> NewsJobUsage {
        NewsJobUsage(
            callCount: calls,
            inputTokens: 8_000,
            outputTokens: 2_000,
            totalCostUSD: 0.4,
            plannedItems: 10,
            primaryPercentDelta: nil,
            primaryWindowMinutes: nil,
            secondaryPercentDelta: nil,
            secondaryWindowMinutes: nil,
            planType: nil
        )
    }

    private func make() -> (NewsViewModel, FakeRepository, FakePipeline) {
        let repository = FakeRepository()
        let pipeline = FakePipeline()
        return (NewsViewModel(repository: repository, pipeline: pipeline), repository, pipeline)
    }

    // MARK: - 목록

    /// **색인에 있어도 파일이 없으면 목록에서 뺀다.** 사용자가 Finder 에서 지웠을 수 있다.
    func testReportsWithMissingFilesAreHidden() {
        let (viewModel, repository, _) = make()
        repository.reports = [report("a", fileName: "a.md"), report("b", fileName: "b.md")]
        viewModel.reload()

        let files = StubFileManager()
        let base = "/base"
        files.existingPaths = [
            NewsReportArchiveStore.configuredReportURL(reportPath: "/anywhere/a.md", dataBasePath: base).path
        ]

        let available = viewModel.availableReports(dataBasePath: base, fileManager: files)

        XCTAssertEqual(available.map(\.jobId), ["a"])
    }

    func testReloadReadsRepository() {
        let (viewModel, repository, _) = make()
        repository.reports = [report("a", fileName: "a.md")]
        repository.jobs = [job(provider: "claude", usage: usage(calls: 20))]

        viewModel.reload()

        XCTAssertEqual(repository.reportFetchCount, 1)
        XCTAssertEqual(viewModel.reports.count, 1)
        XCTAssertEqual(viewModel.jobs.count, 1)
    }

    // MARK: - 소모량

    /// 소모량을 보고하지 않는 provider 로 한 번 돌렸다고 직전 실측치가 사라지면 안 된다.
    func testLastReportedUsageSkipsJobsWithoutUsage() {
        let (viewModel, repository, _) = make()
        repository.jobs = [
            job(provider: "opencode", usage: nil),
            job(provider: "claude", usage: usage(calls: 20))
        ]
        viewModel.reload()

        XCTAssertEqual(viewModel.lastReportedUsage?.callCount, 20)
    }

    func testLastReportedUsageIsNilWhenNothingReported() {
        let (viewModel, repository, _) = make()
        repository.jobs = [job(provider: "opencode", usage: nil)]
        viewModel.reload()

        XCTAssertNil(viewModel.lastReportedUsage)
    }

    /// ollama 는 무료라 추정하지 않는다.
    func testOllamaHasNoUsageEstimate() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        XCTAssertNil(
            viewModel.usageEstimate(
                provider: "ollama",
                interestKeywords: ["AI"],
                youtubeChannelIds: [],
                maxItemsPerSource: 5
            )
        )
    }

    func testEstimateUsesPastJobsOfSameProvider() throws {
        let (viewModel, repository, _) = make()
        repository.jobs = (0..<3).map { _ in job(provider: "claude", usage: usage(calls: 20)) }
        viewModel.reload()

        let estimate = try XCTUnwrap(
            viewModel.usageEstimate(
                provider: "claude",
                interestKeywords: ["AI"],
                youtubeChannelIds: [],
                maxItemsPerSource: 5
            )
        )

        XCTAssertEqual(estimate.sampleCount, 3)
        XCTAssertGreaterThan(estimate.plannedItems, 0)
    }

    // MARK: - 실행

    func testLaunchGoesThroughGateway() {
        let (viewModel, _, pipeline) = make()

        viewModel.launchPipeline()

        XCTAssertEqual(pipeline.launchCount, 1)
    }
}
