import Foundation

/// 설정 항목을 찾아주는 색인.
///
/// 주제마다 규칙을 손으로 쓰지 않는다. 앱에는 이미 설정 사이드바 검색이 쓰는
/// `SettingsTab.searchKeywords` 라는 색인이 있으므로 그것을 그대로 근거로 쓴다.
/// 설정에 새 항목이 생기면 그 목록만 갱신하면 검색과 호로롱 답변이 함께 최신이 된다.
enum CompanionSettingsIndex {
    struct Match: Equatable, Sendable {
        let tab: SettingsTab
        let score: Int

        /// 모델에게 넘길 근거. 짧고 단정할수록 정확했다.
        /// 길게 늘어놓으면 그 안의 다른 이름을 골라 엉뚱한 경로를 만든다.
        var evidence: String {
            "관련 설정은 설정 → \(tab.label) 에 있다."
        }
    }

    /// 질문과 가장 많이 겹치는 설정 페이지. 겹치는 게 없으면 nil.
    static func bestMatch(
        for question: String,
        tabs: [SettingsTab] = SettingsTab.visibleCases
    ) -> Match? {
        let tokens = CompanionGuide.searchTokens(in: question)
        guard !tokens.isEmpty else { return nil }

        var best: Match?
        for tab in tabs {
            var score = 0
            let label = tab.label.lowercased()
            for token in tokens {
                // 항목 이름에 직접 걸리는 편이 페이지 이름보다 확실한 단서다.
                if tab.searchKeywords.contains(where: { $0.lowercased().contains(token) }) {
                    score += 4
                }
                if label.contains(token) { score += 3 }
                if tab.subtitle.lowercased().contains(token) { score += 1 }
            }
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                best = Match(tab: tab, score: score)
            }
        }
        return best
    }

}
