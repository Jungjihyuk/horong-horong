import Foundation

/// 현재 설정으로 리포트를 생성하면 얼마나 소모될지에 대한 추정.
///
/// 값이 아니라 범위를 돌려준다. 호출 횟수는 설정에서 결정적으로 계산되지만
/// 호출당 출력 토큰은 실행 전에 알 수 없어 과거 실행으로 보정하기 때문이다.
struct NewsUsageEstimate: Sendable, Equatable {
    enum Confidence: Sendable {
        /// 과거 실행 이력으로 보정한 값.
        case calibrated
        /// 이력이 부족해 프롬프트 상한 기반으로 잡은 초기 추정.
        case coldStart
    }

    var plannedItems: Int
    var callRange: ClosedRange<Int>
    var tokenRange: ClosedRange<Int>
    /// 비용을 보고하는 provider(claude)만 채워진다.
    var costRange: ClosedRange<Double>?
    /// 요금제 사용률을 노출하거나 환산 가능한 provider(claude, codex, antigravity)만 채워진다.
    var primaryPercentRange: ClosedRange<Double>?
    var primaryWindowMinutes: Int?
    var confidence: Confidence
    /// 보정에 쓰인 과거 실행 수.
    var sampleCount: Int
}

/// 과거 실행 이력과 구독 요금제 정책으로 다음 실행의 소모량을 추정한다.
enum NewsUsageEstimator {
    /// 이력이 이만큼 쌓이기 전에는 보정값을 신뢰하지 않고 범위를 넓힌다.
    static let minimumSamplesForConfidence = 3
    /// 보정에 사용할 최근 실행 수.
    static let historyWindow = 10

    /// 이력이 없을 때 쓰는 초기 추정치.
    private static let coldStartTokensPerCall = 1_800.0
    private static let coldStartCallsPerItem = 2.0

    /// - Parameter jobs: 최근 실행 이력. 저장소를 직접 읽지 않고 호출부에서 주입받는다.
    static func estimate(
        provider: String,
        plannedItems: Int,
        jobs: [NewsJobRun]
    ) -> NewsUsageEstimate {
        let samples = jobs
            .lazy
            .filter { $0.provider == provider }
            .prefix(historyWindow)
            .compactMap { sample(from: $0, provider: provider) }

        return estimate(provider: provider, plannedItems: plannedItems, samples: Array(samples))
    }

    private static func estimate(
        provider: String,
        plannedItems: Int,
        samples: [Sample]
    ) -> NewsUsageEstimate {
        let rule = NewsSubscriptionPolicy.rule(for: provider)

        guard !samples.isEmpty else {
            return coldStartEstimate(provider: provider, plannedItems: plannedItems, rule: rule)
        }

        let callsPerItem = median(samples.map(\.callsPerItem))
        let tokensPerCall = median(samples.map(\.tokensPerCall))
        let calls = callsPerItem * Double(plannedItems)
        let tokens = tokensPerCall * calls

        // 표본이 적을수록 범위를 넓힌다.
        let spread = samples.count >= minimumSamplesForConfidence ? 0.25 : 0.6

        let costPerCall = medianOrNil(samples.compactMap(\.costPerCall))
        var percentPerCall = medianOrNil(samples.compactMap(\.primaryPercentPerCall))

        // percentPerCall이 없거나 0.0001 이하이고 요금제 룰이 있는 경우 토큰/비용으로부터 보정
        if (percentPerCall == nil || percentPerCall! <= 0.0001), let rule {
            percentPerCall = rule.calculatePercent(tokens: Int(tokensPerCall), costUSD: costPerCall)
        }

        let primaryPercentRange: ClosedRange<Double>?
        if let percentPerCall, percentPerCall > 0 {
            primaryPercentRange = doubleRange(percentPerCall * calls, spread: spread)
        } else {
            primaryPercentRange = nil
        }

        let primaryWindowMinutes = samples.compactMap(\.primaryWindowMinutes).first ?? rule?.windowMinutes

        return NewsUsageEstimate(
            plannedItems: plannedItems,
            callRange: intRange(calls, spread: spread),
            tokenRange: intRange(tokens, spread: spread),
            costRange: costPerCall.map { doubleRange($0 * calls, spread: spread) },
            primaryPercentRange: primaryPercentRange,
            primaryWindowMinutes: primaryWindowMinutes,
            confidence: samples.count >= minimumSamplesForConfidence ? .calibrated : .coldStart,
            sampleCount: samples.count
        )
    }

    // MARK: - Private

    /// 보정에 쓸 수 있는 과거 실행 1건.
    private struct Sample {
        var callsPerItem: Double
        var tokensPerCall: Double
        var costPerCall: Double?
        var primaryPercentPerCall: Double?
        var primaryWindowMinutes: Int?
    }

    private static func sample(from job: NewsJobRun, provider: String) -> Sample? {
        guard
            let usage = job.usage, usage.callCount > 0,
            let plannedItems = usage.plannedItems, plannedItems > 0,
            let input = usage.inputTokens,
            let output = usage.outputTokens
        else { return nil }

        let callCount = Double(usage.callCount)
        let totalTokens = usage.totalTokens ?? (input + output)
        let costPerCall = usage.totalCostUSD.map { $0 / callCount }

        var percentPerCall: Double?
        if let delta = usage.primaryPercentDelta, delta > 0.0001 {
            percentPerCall = delta / callCount
        } else if let rule = NewsSubscriptionPolicy.rule(for: provider) {
            // 과거 기록에 delta가 없거나 0인 경우 구독 정책으로 환산
            if let percent = rule.calculatePercent(tokens: totalTokens, costUSD: usage.totalCostUSD) {
                percentPerCall = percent / callCount
            }
        }

        let windowMinutes = usage.primaryWindowMinutes ?? NewsSubscriptionPolicy.rule(for: provider)?.windowMinutes

        return Sample(
            callsPerItem: callCount / Double(plannedItems),
            tokensPerCall: Double(totalTokens) / callCount,
            costPerCall: costPerCall,
            primaryPercentPerCall: percentPerCall,
            primaryWindowMinutes: windowMinutes
        )
    }

    private static func coldStartEstimate(
        provider: String,
        plannedItems: Int,
        rule: NewsSubscriptionRule?
    ) -> NewsUsageEstimate {
        let calls = coldStartCallsPerItem * Double(plannedItems)
        let tokens = coldStartTokensPerCall * calls

        var primaryPercentRange: ClosedRange<Double>?
        var primaryWindowMinutes: Int?

        if let rule {
            if let percent = rule.calculatePercent(tokens: Int(tokens), costUSD: nil) {
                primaryPercentRange = doubleRange(percent, spread: 0.6)
                primaryWindowMinutes = rule.windowMinutes
            }
        }

        return NewsUsageEstimate(
            plannedItems: plannedItems,
            callRange: intRange(calls, spread: 0.6),
            tokenRange: intRange(tokens, spread: 0.6),
            costRange: nil,
            primaryPercentRange: primaryPercentRange,
            primaryWindowMinutes: primaryWindowMinutes,
            confidence: .coldStart,
            sampleCount: 0
        )
    }

    private static func intRange(_ center: Double, spread: Double) -> ClosedRange<Int> {
        let low = max(0, Int((center * (1 - spread)).rounded()))
        let high = max(low, Int((center * (1 + spread)).rounded()))
        return low...high
    }

    private static func doubleRange(_ center: Double, spread: Double) -> ClosedRange<Double> {
        let low = max(0, center * (1 - spread))
        let high = max(low, center * (1 + spread))
        return low...high
    }

    private static func median(_ values: [Double]) -> Double {
        medianOrNil(values) ?? 0
    }

    private static func medianOrNil(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
