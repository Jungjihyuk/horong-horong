import SwiftUI

/// 소모량 표시 문구를 만드는 헬퍼.
///
/// Provider마다 알 수 있는 정보가 달라 표시도 다르다. Codex처럼 요금제
/// 사용률을 노출하는 provider만 "%"를 쓰고, Claude처럼 잔여 한도를 알 수 없는
/// provider는 토큰과 비용만 보여준다. 알 수 없는 값을 추정해서 % 로 보여주면
/// 사용자가 실제와 다른 숫자를 믿게 되므로 그렇게 하지 않는다.
enum NewsUsageFormat {
    /// 한도 창 길이를 사람이 읽는 문구로 바꾼다.
    ///
    /// 요금제마다 창이 다르므로(Codex pro는 300분/10080분, free는 43200분)
    /// 값에서 유도한다.
    static func windowLabel(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes)분" }
        if minutes < 1440 { return "\(minutes / 60)시간" }
        return "\(minutes / 1440)일"
    }

    static func tokens(_ value: Int) -> String {
        if value < 10_000 {
            return value.formatted(.number.grouping(.automatic))
        }
        return value.formatted(.number.notation(.compactName))
    }

    static func tokenRange(_ range: ClosedRange<Int>) -> String {
        "\(tokens(range.lowerBound))~\(tokens(range.upperBound))"
    }

    static func cost(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(2)))
    }

    static func costRange(_ range: ClosedRange<Double>) -> String {
        "\(cost(range.lowerBound))~\(cost(range.upperBound))"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 1 ? 2 : 1))) + "%"
    }

    static func percentRange(_ range: ClosedRange<Double>) -> String {
        "\(percent(range.lowerBound))~\(percent(range.upperBound))"
    }
}

/// 실행 전 예상 소모량 한 줄.
struct NewsUsageEstimateLabel: View {
    let estimate: NewsUsageEstimate

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11))
            if estimate.confidence == .coldStart {
                Text("추정")
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .foregroundStyle(PopoverChrome.inkSecondary)
        .help(helpText)
    }

    private var text: String {
        // 사용률을 알 수 있는 provider는 "몇 % 차감"이 가장 직접적인 정보다.
        if let percentRange = estimate.primaryPercentRange {
            let window = NewsUsageFormat.windowLabel(minutes: estimate.primaryWindowMinutes)
            let suffix = window.map { " (\($0) 한도)" } ?? ""
            return "예상 \(NewsUsageFormat.percentRange(percentRange)) 차감\(suffix)"
        }

        var parts = ["예상 \(NewsUsageFormat.tokenRange(estimate.tokenRange)) 토큰"]
        if let costRange = estimate.costRange {
            parts.append(NewsUsageFormat.costRange(costRange))
        }
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        let base = "아이템 \(estimate.plannedItems)개 기준 "
            + "\(estimate.callRange.lowerBound)~\(estimate.callRange.upperBound)회 호출 예상"
        switch estimate.confidence {
        case .calibrated:
            return base + "\n최근 실행 \(estimate.sampleCount)회로 보정한 값입니다."
        case .coldStart:
            return estimate.sampleCount == 0
                ? base + "\n아직 실행 이력이 없어 넓은 초기 추정치입니다."
                : base + "\n실행 이력이 \(estimate.sampleCount)회뿐이라 범위가 넓습니다."
        }
    }
}

/// 마지막 실행의 실제 소모량 한 줄.
struct NewsUsageActualLabel: View {
    let usage: NewsJobUsage

    var body: some View {
        if let text {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.gauge")
                    .font(.system(size: 9))
                Text(text)
                    .font(.system(size: 11))
            }
            .foregroundStyle(PopoverChrome.inkSecondary)
            .help(helpText ?? text)
        }
    }

    private var text: String? {
        if let delta = usage.primaryPercentDelta {
            let window = NewsUsageFormat.windowLabel(minutes: usage.primaryWindowMinutes)
            let suffix = window.map { " (\($0))" } ?? ""
            var line = "이번 실행 \(NewsUsageFormat.percent(delta)) 차감\(suffix)"
            if let secondary = usage.secondaryPercentDelta,
               let secondaryWindow = NewsUsageFormat.windowLabel(
                   minutes: usage.secondaryWindowMinutes
               ) {
                line += " · \(secondaryWindow) \(NewsUsageFormat.percent(secondary))"
            }
            return line
        }

        guard let input = usage.inputTokens, let output = usage.outputTokens else {
            // 소모량을 보고하지 않는 provider는 아무것도 표시하지 않는다.
            return nil
        }
        var parts = ["이번 실행 \(NewsUsageFormat.tokens(input + output)) 토큰"]
        if let cost = usage.totalCostUSD {
            parts.append(NewsUsageFormat.cost(cost))
        }
        return parts.joined(separator: " · ")
    }

    private var helpText: String? {
        let calls = usage.callCount
        var lines = ["\(calls)회 호출"]
        if let plan = usage.planType {
            lines.append("요금제: \(plan)")
        }
        if usage.primaryPercentDelta == nil, usage.totalCostUSD != nil {
            lines.append("이 provider는 구독 잔여 한도를 조회할 수 없어 % 대신 토큰·비용을 표시합니다.")
        }
        return lines.joined(separator: "\n")
    }
}
