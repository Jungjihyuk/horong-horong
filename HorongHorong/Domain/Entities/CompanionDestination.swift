import Foundation

/// 루미롱이 안내할 수 있는 앱 내부 목적지의 안정적인 식별자다.
struct CompanionDestinationID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let theme = Self(rawValue: "settings.theme")
    static let appearanceMode = Self(rawValue: "settings.appearanceMode")
    static let launchAtLogin = Self(rawValue: "settings.launchAtLogin")
    static let companionBasics = Self(rawValue: "settings.companionBasics")
    static let globalHotkeys = Self(rawValue: "settings.globalHotkeys")
    static let remindersImport = Self(rawValue: "settings.remindersImport")
    static let achievement = Self(rawValue: "settings.achievement")
    static let focus = Self(rawValue: "settings.focus")
    static let data = Self(rawValue: "settings.data")
    static let newsSources = Self(rawValue: "settings.newsSources")
    // 팝오버
    static let popoverTimer = Self(rawValue: "popover.timer")
    static let popoverTimerPreset = Self(rawValue: "popover.timer.preset")
    static let popoverTimerSelectTask = Self(rawValue: "popover.timer.selectTask")
    static let popoverTimerStartFocus = Self(rawValue: "popover.timer.startFocus")
    static let popoverMemo = Self(rawValue: "popover.memo")
    static let popoverMemoNew = Self(rawValue: "popover.memo.new")
    static let popoverStats = Self(rawValue: "popover.stats")
    static let popoverStatsDetail = Self(rawValue: "popover.stats.detail")
    static let popoverNews = Self(rawValue: "popover.news")
    static let popoverLab = Self(rawValue: "popover.lab")
    static let popoverAchievement = Self(rawValue: "popover.achievement")

    // 허브
    static let hubMemo = Self(rawValue: "hub.memo")
    static let hubMemoQuick = Self(rawValue: "hub.memo.quick")
    static let hubMemoDiary = Self(rawValue: "hub.memo.diary")
    static let hubMemoTodo = Self(rawValue: "hub.memo.todo")
    static let hubMemoRefs = Self(rawValue: "hub.memo.refs")
    static let hubNews = Self(rawValue: "hub.news")
    static let hubStats = Self(rawValue: "hub.stats")
    static let hubStatsFocusToggle = Self(rawValue: "hub.stats.focusToggle")
    static let hubAchievement = Self(rawValue: "hub.achievement")
}

/// UI 프레임워크 타입을 노출하지 않는 앱 내부 목적지 값이다.
struct CompanionDestination: Equatable, Sendable {
    enum Surface: String, Equatable, Sendable {
        case settings
        case popover
        case hub
    }

    let id: CompanionDestinationID
    let surface: Surface
    /// Presentation 계층이 자기 화면 enum으로 해석하는 안정적인 섹션 식별자다.
    let sectionID: String
    /// 화면 안에서 스크롤하고 강조할 요소. 없으면 섹션만 연다.
    let targetID: String?
}
