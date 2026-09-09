import Foundation

/// 만들어진 리포트 한 편의 색인.
///
/// **값 타입이다.** 저장은 `NewsReportIndex`(`@Model`)가 하지만 그건 Data 계층에 남는다.
///
/// 본문은 여기 없다 — 리포트는 파일로 남고 DB 에는 어디 있는지만 적는다.
struct NewsReport: Identifiable, Equatable, Sendable {
    let jobId: String
    let reportDate: Date
    let reportPath: String
    let metaPath: String
    let topTitle: String
    let itemCount: Int
    let createdAt: Date

    var id: String { jobId }
}

/// 파이프라인 실행 한 번의 기록.
struct NewsJobRun: Identifiable, Equatable, Sendable {
    let jobId: String
    let status: String
    let provider: String
    let requestedAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let errorCode: String?
    let errorMessage: String?
    let logPath: String?
    /// 소모량. **`nil` 이면 이 실행은 소모량을 보고하지 않았다** —
    /// provider 가 안 알려주거나 아직 기록되기 전이다.
    let usage: NewsJobUsage?

    var id: String { jobId }
}

/// 실행 한 번이 쓴 양. 다음 실행을 예측하는 재료다.
///
/// `callCount` 만 옵셔널이 아닌 이유: 이 값이 없으면 나머지를 «호출당» 으로 환산할 수 없어
/// 표본으로 쓸 수 없다. 그래서 `NewsJobUsage` 자체가 만들어지지 않는다.
struct NewsJobUsage: Equatable, Sendable {
    let callCount: Int
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheHitTokens: Int?
    let cacheWriteTokens: Int?
    let cacheStorage5mTokens: Int?
    let cacheStorage1hTokens: Int?
    let reasoningOutputTokens: Int?
    let totalCostUSD: Double?
    /// 이 실행이 다루기로 한 아이템 수. 설정이 달랐던 과거 실행을 지금 설정으로 환산할 때 쓴다.
    let plannedItems: Int?
    let primaryPercentDelta: Double?
    let primaryWindowMinutes: Int?
    let secondaryPercentDelta: Double?
    let secondaryWindowMinutes: Int?
    let planType: String?

    init(
        callCount: Int,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheHitTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        cacheStorage5mTokens: Int? = nil,
        cacheStorage1hTokens: Int? = nil,
        reasoningOutputTokens: Int? = nil,
        totalCostUSD: Double? = nil,
        plannedItems: Int? = nil,
        primaryPercentDelta: Double? = nil,
        primaryWindowMinutes: Int? = nil,
        secondaryPercentDelta: Double? = nil,
        secondaryWindowMinutes: Int? = nil,
        planType: String? = nil
    ) {
        self.callCount = callCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheStorage5mTokens = cacheStorage5mTokens
        self.cacheStorage1hTokens = cacheStorage1hTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalCostUSD = totalCostUSD
        self.plannedItems = plannedItems
        self.primaryPercentDelta = primaryPercentDelta
        self.primaryWindowMinutes = primaryWindowMinutes
        self.secondaryPercentDelta = secondaryPercentDelta
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.planType = planType
    }

    /// 캐시 적중/생성 토큰을 모두 포함한 실제 처리 토큰 합계.
    var totalTokens: Int? {
        guard let input = inputTokens, let output = outputTokens else { return nil }
        return input + output + (cacheHitTokens ?? 0) + (cacheWriteTokens ?? 0)
    }
}
