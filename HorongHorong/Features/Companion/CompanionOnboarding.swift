import Foundation

/// 온보딩 한 단계에서 띄울 화면.
enum CompanionOnboardingScreen: String, Equatable, Sendable {
    case popoverTimer = "popover.timer"
    case popoverMemo = "popover.memo"
    case popoverStats = "popover.stats"
    case popoverAchievement = "popover.achievement"
    case windowStats = "window.stats"
    case settingsCompanion = "settings.companion"
}

struct CompanionOnboardingStep: Equatable, Sendable {
    let title: String
    /// 호로롱이 말할 문장.
    let line: String
    let screen: CompanionOnboardingScreen?
}

struct CompanionOnboardingScenario: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let steps: [CompanionOnboardingStep]
}

/// `Resources/Guide/onboarding.md` 를 읽어 단계 목록으로 바꾼다.
///
/// 문서는 사람이 읽고 고치는 것이 먼저다. 그래서 기계용 표시는 HTML 주석으로만 두어
/// GitHub 에서 렌더링될 때 보이지 않게 했다.
enum CompanionOnboardingScript {
    static let resourceName = "onboarding"

    /// `## 제목` + 바로 뒤의 `<!-- id: ... -->` 가 있는 것만 시나리오로 본다.
    /// 안내문처럼 id 가 없는 `##` 문단은 대본이 아니므로 건너뛴다.
    static func parse(_ markdown: String) -> [CompanionOnboardingScenario] {
        var scenarios: [CompanionOnboardingScenario] = []

        var scenarioTitle: String?
        var scenarioID: String?
        var steps: [CompanionOnboardingStep] = []

        var stepTitle: String?
        var stepScreen: CompanionOnboardingScreen?
        var stepLines: [String] = []

        func flushStep() {
            defer {
                stepTitle = nil
                stepScreen = nil
                stepLines = []
            }
            guard let stepTitle, !stepLines.isEmpty else { return }
            steps.append(
                CompanionOnboardingStep(
                    title: stepTitle,
                    line: stepLines.joined(separator: " "),
                    screen: stepScreen
                )
            )
        }

        func flushScenario() {
            flushStep()
            defer {
                scenarioTitle = nil
                scenarioID = nil
                steps = []
            }
            guard let scenarioID, let scenarioTitle, !steps.isEmpty else { return }
            scenarios.append(
                CompanionOnboardingScenario(id: scenarioID, title: scenarioTitle, steps: steps)
            )
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("## ") {
                flushScenario()
                scenarioTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("### ") {
                flushStep()
                stepTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if let value = comment(named: "id", in: line) {
                // 단계가 시작되기 전에 나온 id 만 시나리오 것으로 본다.
                if stepTitle == nil { scenarioID = value }
                continue
            }

            if let value = comment(named: "screen", in: line) {
                stepScreen = CompanionOnboardingScreen(rawValue: value)
                continue
            }

            if line.hasPrefix(">") {
                let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { stepLines.append(text) }
            }
        }
        flushScenario()

        return scenarios
    }

    /// `<!-- name: value -->` 에서 value 를 꺼낸다.
    private static func comment(named name: String, in line: String) -> String? {
        guard line.hasPrefix("<!--"), line.hasSuffix("-->") else { return nil }
        let inner = line
            .dropFirst(4)
            .dropLast(3)
            .trimmingCharacters(in: .whitespaces)
        let parts = inner.split(separator: ":", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, parts[0] == name, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// 번들에 담긴 대본. 없으면 빈 배열이라 온보딩이 그냥 실행되지 않는다.
    static func loadFromBundle(_ bundle: Bundle = .main) -> [CompanionOnboardingScenario] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(markdown)
    }
}

/// 온보딩을 자동으로 띄울지 판단한다.
enum CompanionOnboardingTrigger {
    /// 아직 본 적이 없고, 쓴 흔적도 전혀 없을 때만 자동 실행한다.
    ///
    /// 플래그만 보면 앱을 지웠다 깔아도 `UserDefaults` 가 남아 다시 안 뜬다.
    /// 데이터만 보면 기록을 모두 지운 기존 사용자에게 다시 뜬다. 그래서 둘 다 본다.
    static func shouldStartAutomatically(
        hasSeenOnboarding: Bool,
        memoCount: Int,
        focusSessionCount: Int
    ) -> Bool {
        guard !hasSeenOnboarding else { return false }
        return memoCount == 0 && focusSessionCount == 0
    }
}
