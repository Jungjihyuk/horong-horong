import Foundation

/// 현재 설정으로 리포트를 생성하면 얼마나 소모될지에 대한 추정.
///
/// 값이 아니라 범위를 돌려준다. 호출 횟수는 설정에서 결정적으로 계산되지만
/// 호출당 출력 토큰은 실행 전에 알 수 없어 과거 실행으로 보정하기 때문이다.
struct NewsUsageEstimate {
    enum Confidence {
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
    /// 요금제 사용률을 노출하는 provider(codex)만 채워진다.
    var primaryPercentRange: ClosedRange<Double>?
    var primaryWindowMinutes: Int?
    var confidence: Confidence
    /// 보정에 쓰인 과거 실행 수.
    var sampleCount: Int
}

/// 과거 실행 이력으로 다음 실행의 소모량을 추정한다.
///
/// 호출 수는 다루는 아이템 수(소스 수 × maxItemsPerSource)에 비례한다는 사실만
/// 가정하고, 파이프라인 단계별 호출 구조는 모델링하지 않는다. 단계 구성이
/// 바뀌어도 이력만 쌓이면 자동으로 따라가기 때문이다.
enum NewsUsageEstimator {
    /// 이력이 이만큼 쌓이기 전에는 보정값을 신뢰하지 않고 범위를 넓힌다.
    static let minimumSamplesForConfidence = 3
    /// 보정에 사용할 최근 실행 수.
    static let historyWindow = 10

    /// 이력이 없을 때 쓰는 초기 추정치.
    ///
    /// 프롬프트가 4000자(relevance) / 5000자(insight)로 잘려 있다는 사실에서
    /// 입력 상한을, 출력은 보수적인 상수로 잡는다. 실행이 한 번이라도 성공하면
    /// 즉시 실측 기반으로 대체된다.
    private static let coldStartTokensPerCall = 1_800.0
    private static let coldStartCallsPerItem = 2.0

    /// - Parameter jobs: 최근 실행 이력. **저장소를 직접 읽지 않는다** — 호출부가 이미
    ///   들고 있는 값을 넘긴다. 순수 함수라 SwiftData 없이 테스트한다.
    static func estimate(
        provider: String,
        plannedItems: Int,
        jobs: [NewsJobRun]
    ) -> NewsUsageEstimate {
        let samples = jobs
            .lazy
            .filter { $0.provider == provider }
            .prefix(historyWindow)
            .compactMap(sample(from:))

        return estimate(plannedItems: plannedItems, samples: Array(samples))
    }

    private static func estimate(
        plannedItems: Int,
        samples: [Sample]
    ) -> NewsUsageEstimate {
        guard !samples.isEmpty else {
            return coldStartEstimate(plannedItems: plannedItems)
        }

        let callsPerItem = median(samples.map(\.callsPerItem))
        let tokensPerCall = median(samples.map(\.tokensPerCall))
        let calls = callsPerItem * Double(plannedItems)
        let tokens = tokensPerCall * calls

        // 표본이 적을수록 범위를 넓힌다.
        let spread = samples.count >= minimumSamplesForConfidence ? 0.25 : 0.6

        let costPerCall = medianOrNil(samples.compactMap(\.costPerCall))
        let percentPerCall = medianOrNil(samples.compactMap(\.primaryPercentPerCall))

        return NewsUsageEstimate(
            plannedItems: plannedItems,
            callRange: intRange(calls, spread: spread),
            tokenRange: intRange(tokens, spread: spread),
            costRange: costPerCall.map { doubleRange($0 * calls, spread: spread) },
            primaryPercentRange: percentPerCall.map { doubleRange($0 * calls, spread: spread) },
            primaryWindowMinutes: samples.compactMap(\.primaryWindowMinutes).first,
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

    private static func sample(from job: NewsJobRun) -> Sample? {
        // 소모량을 보고하지 않는 provider이거나 아직 소모량이 기록되기 전인 실행은 건너뛴다.
        guard
            let usage = job.usage, usage.callCount > 0,
            let plannedItems = usage.plannedItems, plannedItems > 0,
            let input = usage.inputTokens,
            let output = usage.outputTokens
        else { return nil }

        let callCount = Double(usage.callCount)
        return Sample(
            callsPerItem: callCount / Double(plannedItems),
            tokensPerCall: Double(input + output) / callCount,
            costPerCall: usage.totalCostUSD.map { $0 / callCount },
            primaryPercentPerCall: usage.primaryPercentDelta.map { $0 / callCount },
            primaryWindowMinutes: usage.primaryWindowMinutes
        )
    }

    private static func coldStartEstimate(plannedItems: Int) -> NewsUsageEstimate {
        let calls = coldStartCallsPerItem * Double(plannedItems)
        return NewsUsageEstimate(
            plannedItems: plannedItems,
            callRange: intRange(calls, spread: 0.6),
            tokenRange: intRange(coldStartTokensPerCall * calls, spread: 0.6),
            costRange: nil,
            primaryPercentRange: nil,
            primaryWindowMinutes: nil,
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

    /// 평균이 아니라 중앙값을 쓴다. 실패로 조기 종료된 실행이 표본에 섞이면
    /// 평균은 크게 흔들리지만 중앙값은 견딘다.
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
