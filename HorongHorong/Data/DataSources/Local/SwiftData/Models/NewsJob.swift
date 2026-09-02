import Foundation
import SwiftData

@Model
final class NewsJob {
    var jobId: String
    var status: String          // queued, running, partial_success, success, failed
    var provider: String
    var requestedAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var errorCode: String?
    var errorMessage: String?
    var logPath: String?

    // MARK: - 소모량
    //
    // 전부 optional이다. 기존 행이 그대로 마이그레이션되어야 하고, 소모량을
    // 보고하지 않는 provider(antigravity/opencode/hermes/ollama)는 값이 없다.
    // 호출당 단가를 뽑아 다음 실행을 예측하는 데 쓰이므로 usageCallCount가 함께 필요하다.
    var usageInputTokens: Int?
    var usageOutputTokens: Int?
    var usageTotalCostUSD: Double?
    var usageCallCount: Int?

    /// 이 실행이 다루기로 한 아이템 수 (소스 수 × maxItemsPerSource).
    /// 호출 수는 이 값에 비례하므로, 설정이 달랐던 과거 실행을 현재 설정으로
    /// 환산하려면 반드시 함께 저장해야 한다.
    var usagePlannedItems: Int?

    // Codex처럼 요금제 사용률을 노출하는 provider만 채워진다.
    // 창 길이는 요금제마다 달라(pro 300/10080, free 43200) 함께 저장한다.
    var usagePrimaryPercentDelta: Double?
    var usagePrimaryWindowMinutes: Int?
    var usageSecondaryPercentDelta: Double?
    var usageSecondaryWindowMinutes: Int?
    var usagePlanType: String?

    init(jobId: String, provider: String) {
        self.jobId = jobId
        self.status = "queued"
        self.provider = provider
        self.requestedAt = Date()
    }
}
