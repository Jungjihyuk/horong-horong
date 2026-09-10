import Foundation
import HorongAI

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
                keywords: ["단축키", "퀵 메모", "퀵메모"],
                line: "기본 퀵 메모 단축키: ⌘⇧N",
                path: "설정 → 단축키 → 퀵 메모 띄우기",
                destination: Destination(tab: .hotkey, highlight: "card:전역")
            ),
            Fact(
                keywords: ["미리알림", "미리 알림", "reminders", "리마인더"],
                line: "미리알림 연동: 선택한 Apple 미리알림 목록의 미완료 항목을 Todo로 가져오고, 가져온 항목의 변경 사항을 다시 미리알림에 동기화한다.",
                path: "설정 → 기록 → 미리알림 가져오기",
                destination: Destination(tab: .secondBrain, highlight: "card:미리알림 가져오기")
            ),
            Fact(
                keywords: ["todo", "할 일", "할일", "일정 입력", "자연어 일정"],
                line: "Todo: 할 일을 기록하고 자연어로 날짜·시각·소요 시간을 입력하며, 일정 배치·완료·보관·미리알림 연결을 관리한다.",
                path: "기록 허브 → Todo"
            ),
            Fact(
                keywords: ["일기", "diary", "감정", "수면 기록"],
                line: "Diary: 날짜별 일기와 하루 여러 시점의 감정, 취침·기상 시각을 기록하고 달력과 인사이트에서 돌아본다.",
                path: "기록 허브 → Diary"
            ),
            Fact(
                keywords: ["knowledge", "works", "옵시디언", "obsidian", "vault", "보관함"],
                line: "Knowledge와 Works: 각각 지정한 Obsidian 보관함의 마크다운 문서를 폴더 트리로 탐색하고 읽거나 편집한다.",
                path: "기록 허브 → Knowledge 또는 Works"
            ),
            Fact(
                keywords: ["references", "레퍼런스", "빠른 링크", "스티키 노트"],
                line: "References: 웹 링크를 보관하고 검색하며, 항목을 화면 위 스티키 노트로 띄울 수 있다. 기본 빠른 링크 단축키는 ⌘⇧L이다.",
                path: "기록 허브 → References"
            ),
            Fact(
                keywords: ["성취", "주간 목표", "월간 목표", "여정", "보상", "포인트"],
                line: "성취: 메모와 Todo를 주간·월간 목표로 묶고 페르소나·비전과 연결한다. 달성 포인트는 사용자가 만든 보상으로 교환할 수 있다.",
                path: "성취 창",
                destination: Destination(tab: .achievement, highlight: nil)
            ),
            Fact(
                keywords: ["몰입도", "집중 넛지", "잔소리", "기준선"],
                line: "몰입: 집중 세션의 앱·웹 사용 패턴으로 몰입도를 계산하고, 기준선 아래로 떨어지면 설정한 방식으로 호로롱이가 말을 건다.",
                path: "설정 → 몰입",
                destination: Destination(tab: .focus, highlight: nil)
            ),
            Fact(
                keywords: ["백업", "복원", "내보내기", "데이터 위치"],
                line: "데이터: 로컬 저장소 위치를 확인하고 백업·복원·내보내기를 관리한다.",
                path: "설정 → 데이터",
                destination: Destination(tab: .data, highlight: nil)
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
        let lines = evidence(for: message, facts: facts).map(\.text)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
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
    static func destination(for message: String, facts: [Fact]? = nil) -> Destination? {
        matches(message, facts: facts).compactMap(\.destination).first
    }
}
