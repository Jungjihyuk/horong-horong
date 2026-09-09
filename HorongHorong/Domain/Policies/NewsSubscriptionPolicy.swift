import Foundation

/// AI CLI 구독 요금제의 5시간 세션 한도 환산 도메인 규칙.
struct NewsSubscriptionRule: Sendable, Equatable {
    var provider: String
    var planType: String
    var windowMinutes: Int
    var tokensPerPercent: Int?
    var costUSDPerPercent: Double?

    /// 토큰 수 또는 비용으로부터 5시간 세션 소모율(%)을 계산한다.
    func calculatePercent(tokens: Int, costUSD: Double?) -> Double? {
        if let costUSD, let costUSDPerPercent, costUSDPerPercent > 0 {
            let percentFromCost = costUSD / costUSDPerPercent
            return min(100.0, max(0.0, percentFromCost))
        }
        if let tokensPerPercent, tokensPerPercent > 0 {
            let percent = Double(tokens) / Double(tokensPerPercent)
            return min(100.0, max(0.0, percent))
        }
        return nil
    }
}

/// AI CLI 구독 요금제 정책 모음. (Claude Pro, ChatGPT Plus, Google AI Pro)
enum NewsSubscriptionPolicy {
    static let supportedProviders: Set<String> = ["claude", "codex", "antigravity"]

    static let rules: [String: NewsSubscriptionRule] = [
        "claude": NewsSubscriptionRule(
            provider: "claude",
            planType: "Claude Pro",
            windowMinutes: 300,
            tokensPerPercent: 15_000,
            costUSDPerPercent: 0.10
        ),
        "codex": NewsSubscriptionRule(
            provider: "codex",
            planType: "ChatGPT Plus",
            windowMinutes: 300,
            tokensPerPercent: 250_000,
            costUSDPerPercent: nil
        ),
        "antigravity": NewsSubscriptionRule(
            provider: "antigravity",
            planType: "Google AI Pro",
            windowMinutes: 300,
            tokensPerPercent: 500_000,
            costUSDPerPercent: nil
        ),
    ]

    static func rule(for provider: String) -> NewsSubscriptionRule? {
        rules[provider]
    }

    static func isSupported(provider: String) -> Bool {
        supportedProviders.contains(provider)
    }
}
