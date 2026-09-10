import Foundation

/// 루미롱이 알고 있는 앱 기능 지식의 고유 식별자다.
struct CompanionKnowledgeID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let cliSetup = Self(rawValue: "knowledge.cliSetup")
    static let popover = Self(rawValue: "knowledge.popover")
    static let newsReport = Self(rawValue: "knowledge.newsReport")
    static let newsSettings = Self(rawValue: "knowledge.newsSettings")
    static let newsArchive = Self(rawValue: "knowledge.newsArchive")
    static let agentLab = Self(rawValue: "knowledge.agentLab")
    static let agentSettings = Self(rawValue: "knowledge.agentSettings")
    static let timer = Self(rawValue: "knowledge.timer")
    static let timerTask = Self(rawValue: "knowledge.timerTask")
    static let timerSettings = Self(rawValue: "knowledge.timerSettings")
    static let secondBrainHub = Self(rawValue: "knowledge.secondBrainHub")
    static let popoverMemo = Self(rawValue: "knowledge.popoverMemo")
    static let quickNote = Self(rawValue: "knowledge.quickNote")
    static let diary = Self(rawValue: "knowledge.diary")
    static let todo = Self(rawValue: "knowledge.todo")
    static let references = Self(rawValue: "knowledge.references")
    static let obsidianVaults = Self(rawValue: "knowledge.obsidianVaults")
    static let remindersImport = Self(rawValue: "knowledge.remindersImport")
    static let stats = Self(rawValue: "knowledge.stats")
    static let statsDetail = Self(rawValue: "knowledge.statsDetail")
    static let categoryMapping = Self(rawValue: "knowledge.categoryMapping")
    static let categoryPairs = Self(rawValue: "knowledge.categoryPairs")
    static let vacation = Self(rawValue: "knowledge.vacation")
    static let focusNudge = Self(rawValue: "knowledge.focusNudge")
    static let appearance = Self(rawValue: "knowledge.appearance")
    static let launchAtLogin = Self(rawValue: "knowledge.launchAtLogin")
    static let settingsOverview = Self(rawValue: "knowledge.settingsOverview")
    static let companionBasics = Self(rawValue: "knowledge.companionBasics")
    static let companionChat = Self(rawValue: "knowledge.companionChat")
    static let scheduleBriefing = Self(rawValue: "knowledge.scheduleBriefing")
    static let achievement = Self(rawValue: "knowledge.achievement")
    static let achievementSettings = Self(rawValue: "knowledge.achievementSettings")
    static let dataBackup = Self(rawValue: "knowledge.dataBackup")
}

/// 앱의 기능, 사용법, 안내 문구 및 목적지 매핑을 담는 도메인 값 타입이다.
struct CompanionKnowledge: Equatable, Sendable {
    let id: CompanionKnowledgeID
    /// 질문 매칭에 사용할 대표/유의어 키워드 목록
    let keywords: [String]
    /// 기능에 대한 핵심 설명 문장
    let summary: String
    /// 화면으로 직접 안내할 때 보여줄 확정 문장 (있을 경우)
    let directGuidance: String?
    /// 사용자에게 보여줄 직관적인 메뉴/설정 경로
    let path: String?
    /// 연결된 실행 가능한 목적지 ID (있을 경우. 없으면 설명 전용 항목)
    let destinationID: CompanionDestinationID?

    init(
        id: CompanionKnowledgeID,
        keywords: [String],
        summary: String,
        directGuidance: String? = nil,
        path: String? = nil,
        destinationID: CompanionDestinationID? = nil
    ) {
        self.id = id
        self.keywords = keywords
        self.summary = summary
        self.directGuidance = directGuidance
        self.path = path
        self.destinationID = destinationID
    }
}
