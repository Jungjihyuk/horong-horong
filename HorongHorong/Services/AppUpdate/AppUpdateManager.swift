import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdateManager()

    @Published private(set) var statusMessage: String = ""
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var automaticallyChecksForUpdates: Bool = false
    @Published private(set) var lastUpdateCheckDate: Date?

    private var updaterController: SPUStandardUpdaterController?

    var currentVersionText: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(marketing)"
    }

    var isConfigured: Bool {
        guard concreteInfoValue(forKey: "SUFeedURL") != nil,
              concreteInfoValue(forKey: "SUPublicEDKey") != nil else {
            return false
        }
        return true
    }

    private override init() {
        super.init()
        configureUpdaterIfNeeded()
    }

    func checkForUpdates() {
        guard let updaterController, canCheckForUpdates else { return }
        statusMessage = "업데이트 확인 중..."
        updaterController.checkForUpdates(nil)
        refreshState()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        refreshState()
    }

    func refreshState() {
        guard let updater = updaterController?.updater else {
            canCheckForUpdates = false
            automaticallyChecksForUpdates = false
            lastUpdateCheckDate = nil
            statusMessage = "업데이트 채널 설정이 필요합니다."
            return
        }

        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        if statusMessage.isEmpty {
            statusMessage = automaticallyChecksForUpdates
                ? "새 버전을 주기적으로 확인합니다."
                : "자동 확인이 꺼져 있습니다."
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            statusMessage = isNoUpdateError(error)
                ? "최신 버전입니다."
                : "업데이트 확인 실패: \(error.localizedDescription)"
        } else {
            statusMessage = "업데이트 확인을 마쳤습니다."
        }
        refreshState()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        statusMessage = isNoUpdateError(error)
            ? "최신 버전입니다."
            : "업데이트 확인 실패: \(error.localizedDescription)"
        refreshState()
    }

    private func configureUpdaterIfNeeded() {
        guard updaterController == nil else { return }
        guard isConfigured else {
            refreshState()
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        refreshState()
    }

    private func concreteInfoValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), !trimmed.contains("example.com") else {
            return nil
        }
        return trimmed
    }

    private func isNoUpdateError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain && nsError.code == 1001
    }
}
