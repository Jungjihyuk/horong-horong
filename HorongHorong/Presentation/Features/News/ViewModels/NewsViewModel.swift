import Foundation
import Observation

/// 뉴스 팝오버의 저장소 쪽 상태.
///
/// **파이프라인 진행 상황은 여기 없다.** 그건 `NewsPipelineService`(`@Observable`)를 화면이
/// 직접 관찰한다 — 여기로 옮겨 담으면 관찰이 한 겹 늘 뿐 얻는 게 없다.
/// 이 클래스가 맡는 것은 **리포트 목록과 실행 이력**, 그리고 실행 시작이다.
@MainActor
@Observable
final class NewsViewModel {
    private(set) var reports: [NewsReport] = []
    private(set) var jobs: [NewsJobRun] = []

    private let repository: NewsRepository
    private let pipeline: NewsPipelineGateway

    /// 팝오버는 5개만 보여준다. 파일이 지워진 것을 걸러내므로 넉넉히 가져온다.
    private static let reportFetchLimit = 30
    /// 소모량 추정이 보는 과거 실행 범위.
    private static let jobFetchLimit = 20

    init(repository: NewsRepository, pipeline: NewsPipelineGateway) {
        self.repository = repository
        self.pipeline = pipeline
    }

    /// **`@Query` 자동 갱신을 대신한다.** 화면이 나타날 때와 파이프라인이 끝났을 때 부른다
    /// (`.newsPipelineJobFinished`). 리포트는 이 앱이 돌린 실행으로만 늘어나므로 그 둘이면 충분하다.
    func reload() {
        reports = (try? repository.recentReports(limit: Self.reportFetchLimit)) ?? []
        jobs = (try? repository.recentJobs(limit: Self.jobFetchLimit)) ?? []
    }

    func launchPipeline() {
        pipeline.launch()
    }

    /// 색인에는 있지만 **파일이 실제로 남아 있는** 리포트만.
    /// 사용자가 Finder 에서 지웠거나 저장 폴더를 옮겼으면 목록에 있어도 열 수 없다.
    func availableReports(dataBasePath: String, fileManager: FileManager = .default) -> [NewsReport] {
        reports.filter { report in
            let url = NewsReportArchiveStore.configuredReportURL(
                reportPath: report.reportPath,
                dataBasePath: dataBasePath
            )
            return fileManager.fileExists(atPath: url.path)
        }
    }

    /// 소모량이 기록된 가장 최근 실행.
    ///
    /// 소모량을 보고하지 않는 provider 로 돌린 실행은 건너뛴다 — provider 를 바꿔 한 번
    /// 돌렸다고 직전 실측치가 사라지지 않게.
    var lastReportedUsage: NewsJobUsage? {
        jobs.first { $0.usage != nil }?.usage
    }

    /// 현재 설정으로 실행했을 때의 예상 소모량. ollama 는 무료라 추정하지 않는다.
    func usageEstimate(
        provider: String,
        interestKeywords: [String],
        youtubeChannelIds: [String],
        maxItemsPerSource: Int
    ) -> NewsUsageEstimate? {
        guard provider != "ollama" else { return nil }

        let sources = NewsPipelineService.resolvedSources(
            interestKeywords: interestKeywords,
            youtubeChannelIds: youtubeChannelIds
        )
        let plannedItems = sources.count * max(1, maxItemsPerSource)
        guard plannedItems > 0 else { return nil }

        return NewsUsageEstimator.estimate(
            provider: provider,
            plannedItems: plannedItems,
            jobs: jobs
        )
    }
}
