import Foundation

/// 앱에서 나열할 수 있는 사실을 코드에서 직접 만든다.
///
/// 테마 이름·탭 목록처럼 열거형에 이미 정답이 있는 것은 문서로 옮겨 적지 않는다.
/// 옮겨 적으면 기능이 바뀔 때 문서가 낡아 모델이 틀린 답을 하게 된다.
enum CompanionAppFacts {
    /// 답변 뒤에 열어 보여줄 곳.
    struct Destination: Equatable, Sendable {
        let tab: SettingsTab
        let highlight: String?
    }

    struct Fact {
        let keywords: [String]
        let line: String
        /// `설정 → 외관 → 테마` 처럼 한 줄로 읽히는 경로.
        var path: String?
        /// 답하면서 실제로 열어 보여줄 곳.
        var destination: Destination?
    }

    static var all: [Fact] {
        [
            Fact(
                keywords: ["테마", "팝오버 테마", "등불", "랜턴", "픽셀"],
                line: "팝오버 테마: " + Constants.PopoverTheme.allCases
                    .map(\.label)
                    .joined(separator: ", ")
                    + "\n지금 쓰는 테마: " + currentThemeLabel,
                path: "설정 → 외관 → 테마",
                destination: Destination(tab: .appearance, highlight: "settings.theme")
            ),
            Fact(
                keywords: ["화면 모드", "다크", "라이트", "외관"],
                line: "화면 모드: 라이트, 다크, 시스템\n지금 쓰는 모드: " + currentAppearanceLabel,
                path: "설정 → 외관 → 모드",
                destination: Destination(tab: .appearance, highlight: "settings.appearanceMode")
            ),
            Fact(
                keywords: ["탭", "팝오버"],
                line: "팝오버 탭: " + PopoverTab.allCases
                    .map(\.rawValue)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["설정", "설정 창", "설정창"],
                line: "설정 페이지: " + SettingsTab.visibleCases
                    .map(\.label)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["프리셋", "포모도로", "집중 시간", "몇 분"],
                line: "타이머 프리셋: " + Constants.PomodoroPreset.allCases
                    .map { "\($0.rawValue)(\($0.focusMinutes)/\($0.breakMinutes)분)" }
                    .joined(separator: ", "),
                path: "설정 → 타이머 → 프리셋"
            ),
            Fact(
                keywords: ["카테고리"],
                line: "기본 카테고리: " + Constants.defaultCategoryDefinitions
                    .map(\.name)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["컴패니언", "루미롱", "캐릭터"],
                line: "등록된 컴패니언: " + CompanionRegistry.all
                    .map(\.displayName)
                    .joined(separator: ", "),
                path: "설정 → 루미롱",
                destination: Destination(tab: .companion, highlight: "settings.companionBasics")
            ),
            Fact(
                keywords: ["메뉴바", "메뉴 바", "라벨", "표시 형식"],
                line: "메뉴바 라벨 형식: " + Constants.MenubarLabelStyle.allCases
                    .map(\.label)
                    .joined(separator: ", ")
                    + "\n메뉴바 시간 형식: " + Constants.MenubarTimeStyle.allCases
                    .map(\.label)
                    .joined(separator: ", ")
                    + "\n메뉴바 아이콘: " + Constants.MenubarIconStyle.allCases
                    .map(\.label)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["알림", "종료 알림", "완료 알림"],
                line: "타이머 완료 알림 방식: " + Constants.TimerCompletionNotificationStyle.allCases
                    .map(\.label)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["미분류", "등록 안 한 앱", "분류"],
                line: "등록하지 않은 앱 처리: " + Constants.UnmappedAppHandling.allCases
                    .map(\.label)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["휴식 후", "다음 흐름", "복귀"],
                line: "휴식 후 다음 흐름 묻기: " + Constants.PostBreakTransitionPromptMode.allCases
                    .map(\.label)
                    .joined(separator: ", ")
            ),
            Fact(
                keywords: ["agent", "에이전트", "실험"],
                line: "쓸 수 있는 Agent: " + Constants.availableAgentTypes.joined(separator: ", ")
            ),
            Fact(
                keywords: ["메모 아이콘", "메모 분류", "아이콘"],
                line: "메모 아이콘: " + MemoIcon.options.joined(separator: " ")
            ),
            Fact(
                keywords: ["단축키", "퀵 메모", "퀵메모"],
                line: "기본 퀵 메모 단축키: ⌘⇧N",
                path: "설정 → 단축키 → 퀵 메모 띄우기"
            ),
            Fact(
                keywords: ["리포트", "레포트"],
                line: "리포트는 뉴스 탭에서 생성하며, 어떤 자료를 가져올지는 뉴스 설정의 소스 목록을 따른다.",
                path: "설정 → 뉴스 → 소스",
                destination: Destination(tab: .news, highlight: "card:소스")
            ),
        ]
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

    /// 질문에 걸리는 사실을 고른다.
    static func matches(_ message: String, facts: [Fact]? = nil) -> [Fact] {
        let normalized = message.lowercased()
        return (facts ?? all).filter { fact in
            fact.keywords.contains { normalized.contains($0.lowercased()) }
        }
    }

    /// 프롬프트에 넣을 근거. 경로가 있으면 함께 넣어 그대로 답하게 한다.
    static func matching(_ message: String, facts: [Fact]? = nil) -> String? {
        let lines = matches(message, facts: facts).map { fact -> String in
            guard let path = fact.path else { return fact.line }
            return "\(fact.line)\n바꾸는 곳: \(path)"
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// 답하면서 열어 보여줄 곳. 여러 개면 첫 번째만 쓴다.
    static func destination(for message: String, facts: [Fact]? = nil) -> Destination? {
        matches(message, facts: facts).compactMap(\.destination).first
    }
}
