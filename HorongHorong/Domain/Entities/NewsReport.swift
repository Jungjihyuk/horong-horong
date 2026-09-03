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
    let totalCostUSD: Double?
    /// 이 실행이 다루기로 한 아이템 수. 설정이 달랐던 과거 실행을 지금 설정으로 환산할 때 쓴다.
    let plannedItems: Int?
    let primaryPercentDelta: Double?
    let primaryWindowMinutes: Int?
    let secondaryPercentDelta: Double?
    let secondaryWindowMinutes: Int?
    let planType: String?
}
