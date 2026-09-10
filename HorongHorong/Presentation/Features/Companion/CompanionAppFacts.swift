import Foundation
import HorongAI

/// 앱에서 나열할 수 있는 사실을 코드에서 직접 만든다.
///
/// 테마 이름·탭 목록처럼 열거형에 이미 정답이 있는 것은 문서로 옮겨 적지 않는다.
/// 옮겨 적으면 기능이 바뀔 때 문서가 낡아 모델이 틀린 답을 하게 된다.
enum CompanionAppFacts {
    struct Fact {
        let keywords: [String]
        let line: String
        /// 모델을 거치지 않고 그대로 보여줄 짧은 안내. 답이 달라지면 안 되는 진입점에만 둔다.
        var directGuidance: String? = nil
        /// `설정 → 외관 → 테마` 처럼 한 줄로 읽히는 경로.
        var path: String?
        /// 답하면서 실제로 열어 보여줄 곳.
        var destinationID: CompanionDestinationID?
    }

    static var all: [Fact] {
        var facts: [Fact] = []

        for knowledge in CompanionKnowledgeRegistry.all {
            let dynamicLine: String
            switch knowledge.id {
            case .appearance:
                dynamicLine = "팝오버 테마: " + Constants.PopoverTheme.allCases
                    .map(\.label)
                    .joined(separator: ", ")
                    + "\n지금 쓰는 테마: " + currentThemeLabel
                    + "\n화면 모드: 라이트, 다크, 시스템"
                    + "\n지금 쓰는 모드: " + currentAppearanceLabel
            case .popover:
                dynamicLine = "팝오버 탭: " + PopoverTab.allCases
                    .map(\.rawValue)
                    .joined(separator: ", ")
            case .settingsOverview:
                dynamicLine = "설정 페이지: " + SettingsTab.companionGuideCases
                    .map(\.label)
                    .joined(separator: ", ")
            case .timer:
                dynamicLine = "타이머 프리셋: " + Constants.PomodoroPreset.allCases
                    .map { "\($0.rawValue)(\($0.focusMinutes)/\($0.breakMinutes)분)" }
                    .joined(separator: ", ")
            case .categoryMapping:
                dynamicLine = "기본 카테고리: " + Constants.defaultCategoryDefinitions
                    .map(\.name)
                    .joined(separator: ", ")
                    + "\n등록하지 않은 앱 처리: " + Constants.UnmappedAppHandling.allCases
                    .map(\.label)
                    .joined(separator: ", ")
            case .categoryPairs:
                let pairLabels = CategoryPairStore.shared.pairs.map { "\($0.first) ↔ \($0.second)" }
                let pairList = pairLabels.isEmpty ? "없음" : pairLabels.joined(separator: ", ")
                dynamicLine = knowledge.summary
                    + "\n등록된 짝 카테고리: " + pairList
                    + "\n효과: 짝으로 묶인 두 카테고리 간의 앱/웹 전환은 집중 흐트러짐(주의 분산)으로 집계되지 않으며, 타임라인과 집중도 점수에서 연속된 집중으로 유지됩니다."
            case .companionBasics:
                dynamicLine = "등록된 컴패니언: " + CompanionRegistry.all
                    .map(\.displayName)
                    .joined(separator: ", ")
                    + "\n" + knowledge.summary
            case .timerSettings:
                dynamicLine = knowledge.summary
                    + "\n메뉴바 라벨 형식: " + Constants.MenubarLabelStyle.allCases.map(\.label).joined(separator: ", ")
                    + "\n메뉴바 시간 형식: " + Constants.MenubarTimeStyle.allCases.map(\.label).joined(separator: ", ")
                    + "\n타이머 완료 알림 방식: " + Constants.TimerCompletionNotificationStyle.allCases.map(\.label).joined(separator: ", ")
            case .agentLab:
                dynamicLine = knowledge.summary
                    + "\n쓸 수 있는 Agent: " + Constants.availableAgentTypes.joined(separator: ", ")
            default:
                dynamicLine = knowledge.summary
            }

            facts.append(
                Fact(
                    keywords: knowledge.keywords,
                    line: dynamicLine,
                    directGuidance: knowledge.directGuidance,
                    path: knowledge.path,
                    destinationID: knowledge.destinationID
                )
            )
        }

        // 세부 전역 단축키 및 부가 사실 보존
        facts.append(
            Fact(
                keywords: ["단축키", "퀵 메모", "퀵메모"],
                line: "기본 퀵 메모 단축키: ⌘⇧N",
                path: "설정 → 단축키 → 퀵 메모 띄우기",
                destinationID: .globalHotkeys
            )
        )
        facts.append(
            Fact(
                keywords: ["휴식 후", "다음 흐름", "복귀"],
                line: "휴식 후 다음 흐름 묻기: " + Constants.PostBreakTransitionPromptMode.allCases
                    .map(\.label)
                    .joined(separator: ", ")
            )
        )

        return facts
    }

    /// 지금 실제로 켜져 있는 값. 이걸 안 넣으면 모델이 "현재 ○○입니다" 를 지어낸다.
    private static var currentThemeLabel: String {
        Constants.PopoverTheme.normalized(
            rawValue: UserDefaults.standard.string(forKey: Constants.AppStorageKey.popoverTheme)
                ?? Constants.defaultPopoverTheme
        ).label
    }

    private static var currentAppearanceLabel: String {
        switch UserDefaults.standard.string(forKey: Constants.AppStorageKey.appearanceMode) {
        case "light": return "라이트"
        case "dark": return "다크"
        default: return "시스템"
        }
    }

    /// 질문에 걸리는 사실을 고른다. 가장 긴 키워드가 일치하는 사실을 우선 정렬한다.
    static func matches(_ message: String, facts: [Fact]? = nil) -> [Fact] {
        let normalized = message.lowercased()
        let sourceFacts = facts ?? all

        struct ScoredFact {
            let fact: Fact
            let maxLength: Int
            let count: Int
        }

        let scored: [ScoredFact] = sourceFacts.compactMap { fact in
            let matched = fact.keywords.filter { normalized.contains($0.lowercased()) }
            guard !matched.isEmpty else { return nil }
            return ScoredFact(
                fact: fact,
                maxLength: matched.map(\.count).max() ?? 0,
                count: matched.count
            )
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.maxLength != rhs.maxLength {
                    return lhs.maxLength > rhs.maxLength
                }
                return lhs.count > rhs.count
            }
            .map(\.fact)
    }

    /// 프롬프트에 넣을 근거. 경로가 있으면 함께 넣어 그대로 답하게 한다.
    static func matching(_ message: String, facts: [Fact]? = nil) -> String? {
        let lines = evidence(for: message, facts: facts).map(\.text)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// 화면을 함께 열어 주는 확정 안내는 모델 표현에 맡기지 않는다.
    static func directGuidance(for message: String, facts: [Fact]? = nil) -> String? {
        if facts == nil, let guidance = CompanionKnowledgeRegistry.directGuidance(for: message) {
            return guidance
        }
        return matches(message, facts: facts).compactMap(\.directGuidance).first
    }

    /// 같은 근거를 조각 단위로. 합쳐 놓으면 어느 사실이 걸렸는지 되짚을 수 없다.
    ///
    /// 앱 도메인(`Constants.PopoverTheme` · `SettingsTab` · 현재 설정값)을 읽으므로
    /// 패키지로 옮길 수 없다. 경계에서 앱이 `Evidence` 로 바꿔 넘긴다.
    static func evidence(for message: String, facts: [Fact]? = nil) -> [Evidence] {
        matches(message, facts: facts).map { fact in
            let text = fact.path.map { "\(fact.line)\n바꾸는 곳: \($0)" } ?? fact.line
            return Evidence(
                // 첫 키워드가 사실상 이 사실의 이름이다. 줄 내용은 설정값에 따라 바뀌므로 id 로 못 쓴다.
                id: "appFacts.\(fact.keywords.first ?? fact.line)",
                source: "appFacts",
                text: text,
                // 키워드가 걸렸는지만 보므로 순위가 없다. 없는 점수를 지어내지 않는다.
                score: nil
            )
        }
    }

    /// 답하면서 열어 보여줄 곳. 여러 개면 첫 번째만 쓴다.
    static func destination(for message: String, facts: [Fact]? = nil) -> CompanionDestination? {
        if facts == nil, let destID = CompanionKnowledgeRegistry.destinationID(for: message) {
            return CompanionDestinationRegistry.destination(for: destID)
        }
        guard let id = matches(message, facts: facts).compactMap(\.destinationID).first else {
            return nil
        }
        return CompanionDestinationRegistry.destination(for: id)
    }
}
