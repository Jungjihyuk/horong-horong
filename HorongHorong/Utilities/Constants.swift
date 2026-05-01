import SwiftUI

enum Constants {
    // MARK: - 포모도로 프리셋
    enum PomodoroPreset: String, CaseIterable, Identifiable {
        case pomodoro = "포모도로"
        case longFocus = "긴 집중"
        case custom = "커스텀"

        var id: String { rawValue }

        var focusMinutes: Int {
            switch self {
            case .pomodoro: return Constants.defaultPomodoroFocusMinutes
            case .longFocus: return Constants.defaultLongFocusFocusMinutes
            case .custom: return Constants.defaultCustomFocusMinutes
            }
        }

        var breakMinutes: Int {
            switch self {
            case .pomodoro: return Constants.defaultPomodoroBreakMinutes
            case .longFocus: return Constants.defaultLongFocusBreakMinutes
            case .custom: return Constants.defaultCustomBreakMinutes
            }
        }
    }

    // MARK: - 카테고리 색상
    static let categoryColors: [String: Color] = [
        "업무": .brown,
        "개발": .blue,
        "공부": Color(red: 0.65, green: 0.87, blue: 0.35),   // 연두
        "조사": .teal,
        "소통": .orange,
        "엔터": .red,
        "기록": Color(red: 0.53, green: 0.81, blue: 0.92),   // 하늘
        "기타": .gray,
    ]

    // MARK: - 카테고리 이모지
    static let categoryEmoji: [String: String] = [
        "업무": "💼",
        "개발": "💻",
        "공부": "📚",
        "조사": "🔎",
        "소통": "💬",
        "엔터": "🎬",
        "기록": "📓",
        "기타": "📦",
    ]

    static let defaultCategoryDefinitions: [CategoryDefinition] = [
        CategoryDefinition(defaultName: "업무", name: "업무", emoji: "💼"),
        CategoryDefinition(defaultName: "개발", name: "개발", emoji: "💻"),
        CategoryDefinition(defaultName: "공부", name: "공부", emoji: "📚"),
        CategoryDefinition(defaultName: "조사", name: "조사", emoji: "🔎"),
        CategoryDefinition(defaultName: "기록", name: "기록", emoji: "📓"),
        CategoryDefinition(defaultName: "소통", name: "소통", emoji: "💬"),
        CategoryDefinition(defaultName: "엔터", name: "엔터", emoji: "🎬"),
        CategoryDefinition(defaultName: "기타", name: "기타", emoji: "📦"),
    ]

    static func categoryName(_ defaultName: String) -> String {
        CategoryStore.shared.displayName(forDefaultName: defaultName)
    }

    static func defaultName(forCategory category: String) -> String {
        CategoryStore.shared.defaultName(forDisplayName: category)
    }

    static func categoryEmoji(for category: String) -> String {
        CategoryStore.shared.emoji(for: category)
    }

    static func categoryColor(for category: String) -> Color {
        let defaultName = defaultName(forCategory: category)
        return categoryColors[defaultName] ?? categoryColors[category] ?? .gray
    }

    // MARK: - 브라우저 bundle identifier (URL 기반 분류용)
    static let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
    ]

    // MARK: - 엔터 카테고리로 분류할 도메인 키워드 (브라우저 URL 내 포함 여부 검사)
    // label 은 AppUsageRecord 에서 "Google Chrome (YouTube)" 처럼 괄호 안에 표기되는 서비스명
    static let entertainmentURLHosts: [(host: String, label: String)] = [
        ("youtube.com", "YouTube"),
        ("youtu.be", "YouTube"),
        ("netflix.com", "Netflix"),
    ]

    // MARK: - 조사 카테고리로 분류할 URL 규칙
    // 검색 결과, 기술 문서, 블로그, Q&A처럼 자료를 찾고 읽는 흐름만 기본 분류한다.
    static let researchURLRules: [(host: String, pathContains: String?, label: String)] = [
        ("google.com", "/search", "Google Search"),
        ("bing.com", "/search", "Bing Search"),
        ("duckduckgo.com", nil, "DuckDuckGo"),
        ("search.naver.com", nil, "Naver Search"),
        ("search.daum.net", nil, "Daum Search"),
        ("perplexity.ai", nil, "Perplexity"),
        ("wikipedia.org", nil, "Wikipedia"),
        ("developer.mozilla.org", nil, "MDN"),
        ("stackoverflow.com", nil, "Stack Overflow"),
        ("stackexchange.com", nil, "Stack Exchange"),
        ("tistory.com", nil, "Tistory"),
        ("velog.io", nil, "Velog"),
        ("medium.com", nil, "Medium"),
        ("dev.to", nil, "DEV"),
        ("github.io", nil, "GitHub Pages"),
    ]

    // MARK: - 기본 앱→카테고리 매핑 (업무/공부는 자동 매핑 없음)
    static var defaultCategoryRules: [(bundleId: String, appName: String, category: String)] { [
        // 💻 개발
        ("com.microsoft.VSCode", "Visual Studio Code", categoryName("개발")),
        ("com.google.antigravity", "Antigravity", categoryName("개발")),
        ("com.openai.codex", "Codex", categoryName("개발")),
        ("com.anthropic.claudefordesktop", "Claude", categoryName("개발")),
        ("com.cmuxterm.app", "cmux", categoryName("개발")),
        ("com.apple.Terminal", "터미널", categoryName("개발")),
        ("com.googlecode.iterm2", "iTerm2", categoryName("개발")),

        // 📓 기록
        ("md.obsidian", "Obsidian", categoryName("기록")),
        ("notion.id", "Notion", categoryName("기록")),
        ("com.apple.Notes", "메모", categoryName("기록")),
        ("com.apple.reminders", "미리알림", categoryName("기록")),

        // 💬 소통
        ("com.kakao.KakaoTalkMac", "카카오톡", categoryName("소통")),
        ("com.hnc.Discord", "Discord", categoryName("소통")),
    ] }

    // MARK: - 모든 카테고리 목록
    static var allCategories: [String] { CategoryStore.shared.categoryNames }

    static func defaultCategoryRule(for bundleIdentifier: String) -> (bundleId: String, appName: String, category: String)? {
        defaultCategoryRules.first { $0.bundleId == bundleIdentifier }
    }

    // MARK: - 화면에서 숨길 과거/폐기 카테고리 (데이터에 남아있어도 렌더링 제외)
    static let hiddenLegacyCategories: Set<String> = [
        "SNS/엔터테인먼트",
    ]

    // MARK: - 타이머 집중 세션 의사(pseudo) 앱 식별자
    // AppUsageRecord 에 저장할 때 카테고리별로 하나의 행으로 집계되도록 카테고리를 접미사로 사용
    static let focusSessionBundlePrefix = "app.horonghorong.focus"
    static func focusSessionBundleId(for category: String) -> String {
        "\(focusSessionBundlePrefix).\(category)"
    }
    static let focusSessionAppName = "🔥 집중 세션"

    // MARK: - 타이머 기본값
    static var defaultFocusCategory: String { categoryName("업무") }

    // 프리셋별 기본 시간 (사용자가 설정에서 덮어쓸 수 있음)
    static let defaultPomodoroFocusMinutes = 50
    static let defaultPomodoroBreakMinutes = 5
    static let defaultLongFocusFocusMinutes = 100
    static let defaultLongFocusBreakMinutes = 10
    static let defaultCustomFocusMinutes = 60
    static let defaultCustomBreakMinutes = 10

    // UserDefaults 에서 프리셋 시간을 읽되, 값이 없으면(=0) 기본값 사용
    static func storedFocusMinutes(for preset: PomodoroPreset) -> Int {
        let defaults = UserDefaults.standard
        switch preset {
        case .pomodoro:
            let v = defaults.integer(forKey: AppStorageKey.pomodoroFocusMinutes)
            return v > 0 ? v : defaultPomodoroFocusMinutes
        case .longFocus:
            let v = defaults.integer(forKey: AppStorageKey.longFocusFocusMinutes)
            return v > 0 ? v : defaultLongFocusFocusMinutes
        case .custom:
            return defaultCustomFocusMinutes
        }
    }

    static func storedBreakMinutes(for preset: PomodoroPreset) -> Int {
        let defaults = UserDefaults.standard
        switch preset {
        case .pomodoro:
            let v = defaults.integer(forKey: AppStorageKey.pomodoroBreakMinutes)
            return v > 0 ? v : defaultPomodoroBreakMinutes
        case .longFocus:
            let v = defaults.integer(forKey: AppStorageKey.longFocusBreakMinutes)
            return v > 0 ? v : defaultLongFocusBreakMinutes
        case .custom:
            return defaultCustomBreakMinutes
        }
    }

    // MARK: - 유휴 감지 임계값 (초 단위, 카테고리별 기본값)
    // 이 시간 이상 키보드/마우스 입력이 없으면 "자리 비움 가능성"으로 간주하고
    // 사용자가 돌아왔을 때 해당 구간을 작업 시간으로 인정할지 물어본다.
    static let defaultIdleThresholdSeconds: [String: Int] = [
        "개발": 600,   // 10분
        "공부": 600,   // 10분
        "조사": 600,   // 10분
        "업무": 600,   // 10분
        "기록": 600,   // 10분
        "소통": 180,   // 3분 (호흡이 짧은 작업)
        "기타": 480,   // 8분
        "엔터": 1200,  // 20분 (영상 시청 등)
    ]

    // 유휴 감지 기본 임계값 (카테고리 매핑 없는 경우)
    static let fallbackIdleThresholdSeconds: Int = 600

    // UserDefaults 키 prefix — 카테고리명을 suffix로 붙여 사용
    static let idleThresholdUserDefaultsPrefix = "tracker.idleThreshold."

    // 사용자가 "활성" 상태로 복귀했다고 판정하는 유휴 초 상한
    static let idleActiveReturnThresholdSeconds: Double = 3.0

    // MARK: - 팝오버 크기
    static let popoverWidth: CGFloat = 320
    static let popoverMaxHeight: CGFloat = 480

    // MARK: - 퀵 메모 패널 크기
    static let quickMemoPanelWidth: CGFloat = 560
    static let quickMemoPanelMinHeight: CGFloat = 160
    static let quickMemoPanelMaxHeight: CGFloat = 320

    // MARK: - 통계 윈도우 크기
    static let statsWindowWidth: CGFloat = 700
    static let statsWindowHeight: CGFloat = 500

    // MARK: - Agent 실험 설정
    static var defaultAgentRootDirectoryPath: String {
        repositoryRelativePath("Agents", "experiments")
    }
    static let agentIdeaDirectoryName = "ideas"
    static let agentOutputDirectoryName = "outputs"
    static let defaultInterestKeywords = "생산성, 자동화, 학습"
    static let defaultAgentType = "Codex"
    static let defaultPlanDayCount = 5
    static let availableAgentTypes = ["Codex", "Claude", "Gemini"]

    enum AppStorageKey {
        static let agentRootDirectoryPath = "agent.rootDirectoryPath"
        static let ideaDirectoryPath = "agent.ideaDirectoryPath"
        static let outputDirectoryPath = "agent.outputDirectoryPath"
        static let interestKeywords = "agent.interestKeywords"
        static let selectedAgentType = "agent.selectedAgentType"
        static let planDayCount = "agent.planDayCount"
        static let selectedFocusCategory = "timer.selectedFocusCategory"
        static let pomodoroFocusMinutes = "timer.pomodoroFocusMinutes"
        static let pomodoroBreakMinutes = "timer.pomodoroBreakMinutes"
        static let longFocusFocusMinutes = "timer.longFocusFocusMinutes"
        static let longFocusBreakMinutes = "timer.longFocusBreakMinutes"
        static let timelineStartHour = "timeline.startHour"
        static let timelineEndHour = "timeline.endHour"
        static let timelineBucketMinutes = "timeline.bucketMinutes"
    }

    // MARK: - 타임라인 표시 기본값
    static let defaultTimelineStartHour = 0
    static let defaultTimelineEndHour = 24
    static let defaultTimelineBucketMinutes = 30
    static let timelineBucketMinuteOptions: [Int] = [10, 15, 20, 30, 45, 60, 90, 120]

    // MARK: - 뉴스 큐레이션 설정
    static var defaultNewsRunnerPath: String {
        repositoryRelativePath("Agents", "news_report", "runner.py")
    }
    static var defaultNewsDataBasePath: String {
        repositoryRelativePath("Agents", "news_report")
    }
    static let defaultNewsProvider = "claude"
    static let defaultNewsInterestKeywords = "AI, 개발, 생산성, 자동화"
    static let availableNewsProviders = ["claude", "codex", "gemini", "opencode"]
    enum NewsStorageKey {
        static let dataBasePath = "news.dataBasePath"
        static let selectedProvider = "news.selectedProvider"
        static let interestKeywords = "news.interestKeywords"
        static let youtubeChannelIds = "news.youtube.channelIds"
    }

    static func agentIdeaDirectoryPath(for rootDirectoryPath: String) -> String {
        appendPath(rootDirectoryPath, agentIdeaDirectoryName)
    }

    static func agentOutputDirectoryPath(for rootDirectoryPath: String) -> String {
        appendPath(rootDirectoryPath, agentOutputDirectoryName)
    }

    private static func repositoryRelativePath(_ components: String...) -> String {
        guard let root = repositoryRootPath else { return "" }
        return components.reduce(URL(fileURLWithPath: root, isDirectory: true)) { url, component in
            url.appendingPathComponent(component)
        }.path
    }

    private static var repositoryRootPath: String? {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: sourceURL.appendingPathComponent("project.yml").path) else {
            return nil
        }
        return sourceURL.path
    }

    private static func appendPath(_ rootPath: String, _ component: String) -> String {
        let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .appendingPathComponent(component, isDirectory: true)
            .path
    }
}

struct CategoryDefinition: Codable, Identifiable, Hashable {
    var id: String { name }
    var defaultName: String
    var name: String
    var emoji: String
}

@Observable
final class CategoryStore: @unchecked Sendable {
    static let shared = CategoryStore()

    private let storageKey = "categories.v1"
    private(set) var categories: [CategoryDefinition] = []

    var categoryNames: [String] {
        categories.map(\.name)
    }

    private init() {
        load()
    }

    func emoji(for category: String) -> String {
        categories.first { $0.name == category }?.emoji
            ?? Constants.categoryEmoji[category]
            ?? "📦"
    }

    func displayName(forDefaultName defaultName: String) -> String {
        categories.first { $0.defaultName == defaultName }?.name ?? defaultName
    }

    func defaultName(forDisplayName displayName: String) -> String {
        categories.first { $0.name == displayName }?.defaultName ?? displayName
    }

    func canDelete(_ category: String) -> Bool {
        defaultName(forDisplayName: category) != "기타"
    }

    func add(name: String, emoji: String) -> Bool {
        let trimmed = normalizedName(name)
        guard !trimmed.isEmpty, !categoryNames.contains(trimmed) else { return false }
        categories.append(CategoryDefinition(defaultName: trimmed, name: trimmed, emoji: normalizedEmoji(emoji)))
        save()
        return true
    }

    func update(oldName: String, newName: String, emoji: String) -> Bool {
        let trimmed = normalizedName(newName)
        guard !trimmed.isEmpty else { return false }
        guard trimmed == oldName || !categoryNames.contains(trimmed) else { return false }
        guard let index = categories.firstIndex(where: { $0.name == oldName }) else { return false }
        categories[index].name = trimmed
        categories[index].emoji = normalizedEmoji(emoji)
        save()
        return true
    }

    func delete(name: String) {
        guard canDelete(name) else { return }
        categories.removeAll { $0.name == name }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CategoryDefinition].self, from: data),
           !decoded.isEmpty {
            categories = mergedWithNewDefaults(decoded)
        } else {
            categories = Constants.defaultCategoryDefinitions
        }
        save()
    }

    private func mergedWithNewDefaults(_ decoded: [CategoryDefinition]) -> [CategoryDefinition] {
        var result = decoded
        let existingDefaultNames = Set(decoded.map(\.defaultName))
        for category in Constants.defaultCategoryDefinitions where !existingDefaultNames.contains(category.defaultName) {
            result.append(category)
        }
        return result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedEmoji(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "📦" : trimmed
    }
}
