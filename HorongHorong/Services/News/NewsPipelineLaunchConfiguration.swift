import Foundation
import SwiftData

/// 뉴스 파이프라인을 띄우는 데 필요한 인자 묶음.
///
/// `NewsPipelineService.startJob` 은 UserDefaults 를 전혀 읽지 않고 파라미터만 받는다.
/// 그 조립 로직이 원래 `NewsView` 안에만 있어서 팝오버를 열지 않는 경로(자동 수집 스케줄러)에서
/// 재사용할 수 없었다. 그래서 View 밖으로 꺼내 둔다.
struct NewsPipelineLaunchConfiguration {
    var provider: String
    var providerOptions: NewsProviderOptionsPayload?
    var runnerPath: String
    var dataBasePath: String
    var interestKeywords: [String]
    var youtubeChannelIds: [String]
    var maxItemsPerSource: Int

    static func current(defaults: UserDefaults = .standard) -> Self {
        let provider = defaults.string(forKey: Constants.NewsStorageKey.selectedProvider)
            ?? Constants.defaultNewsProvider

        let storedBasePath = defaults.string(forKey: Constants.NewsStorageKey.dataBasePath)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return Self(
            provider: provider,
            providerOptions: provider == "ollama" ? ollamaOptions(defaults: defaults) : nil,
            runnerPath: Constants.defaultNewsRunnerPath,
            dataBasePath: storedBasePath.isEmpty ? Constants.defaultNewsDataBasePath : storedBasePath,
            interestKeywords: csvList(defaults.string(forKey: Constants.NewsStorageKey.interestKeywords)),
            youtubeChannelIds: csvList(defaults.string(forKey: Constants.NewsStorageKey.youtubeChannelIds)),
            maxItemsPerSource: defaults.object(forKey: Constants.NewsStorageKey.maxItemsPerSource) as? Int
                ?? Constants.defaultNewsMaxItemsPerSource
        )
    }

    /// 잡을 시작하고 "마지막으로 수집을 시작한 시각" 을 기록한다.
    ///
    /// 수동·자동 실행이 모두 이 경로를 지나므로 `scheduleLastRunAt` 이 한 곳에서만 갱신된다.
    /// 기록 시점을 완료가 아니라 시작으로 잡은 이유는, 잡이 즉시 실패해도 한 슬롯은 쉬어
    /// 재시도가 몰리지 않게 하기 위해서다.
    @MainActor
    func launch(
        on service: NewsPipelineService,
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(Date().timeIntervalSince1970, forKey: Constants.NewsStorageKey.scheduleLastRunAt)
        service.startJob(
            provider: provider,
            providerOptions: providerOptions,
            runnerPath: runnerPath,
            dataBasePath: dataBasePath,
            interestKeywords: interestKeywords,
            youtubeChannelIds: youtubeChannelIds,
            maxItemsPerSource: maxItemsPerSource,
            context: context
        )
    }

    // MARK: - Private

    private static func ollamaOptions(defaults: UserDefaults) -> NewsProviderOptionsPayload {
        let model = defaults.string(forKey: Constants.NewsStorageKey.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let endpoint = defaults.string(forKey: Constants.NewsStorageKey.ollamaEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeout = defaults.object(forKey: Constants.NewsStorageKey.ollamaTimeout) as? Double
            ?? Constants.defaultNewsOllamaTimeout
        return NewsProviderOptionsPayload(
            model: model.isEmpty ? Constants.defaultNewsOllamaModel : model,
            endpoint: endpoint.isEmpty ? Constants.defaultNewsOllamaEndpoint : endpoint,
            timeout: timeout
        )
    }

    private static func csvList(_ raw: String?) -> [String] {
        (raw ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
