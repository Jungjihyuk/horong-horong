import SwiftUI

enum Constants {
    /// 앱의 사용 구간은 기록했지만 사용자가 아직 카테고리를 확정하지 않은 상태.
    /// 실제 사용자 카테고리 목록에는 포함하지 않는다.
    static let unclassifiedAppCategory = "미분류"
    /// 타이머·할 일 확인처럼 작업 흐름을 관리하기 위해 잠깐 사용하는 앱의 특수 분류.
    static let productivityManagementAppCategory = "생산성 관리"
    static let productivityManagementAppEmoji = "⏰"
    static let legacySupportAppCategory = "세션 보조"
    static let horongHorongBundleIdentifier = "com.horonghorong.app"
    static let productivityManagementShortInteractionSeconds: TimeInterval = 10
    static let productivityManagementReflectionThresholdSeconds = 60
    static let reservedCategoryNames: Set<String> = [
        unclassifiedAppCategory,
        productivityManagementAppCategory,
        legacySupportAppCategory,
    ]

    static func isProductivityManagementCategory(_ category: String) -> Bool {
        category == productivityManagementAppCategory
            || category == legacySupportAppCategory
    }

    static func mondayWeekStart(for date: Date, calendar baseCalendar: Calendar = .current) -> Date {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
            ?? calendar.startOfDay(for: date)
    }

    struct NewsOllamaModelOption: Identifiable, Hashable {
        enum Availability: Hashable {
            case local
            case cloud
        }

        var id: String { name }
        let name: String
        let label: String
        let detail: String
        let availability: Availability
        let isRecommended: Bool
    }

    enum NewsOllamaRecommendationKind: String {
        case primary = "추천"
        case lightweight = "가벼움"
        case quality = "고품질"
        case caution = "주의"
        case unsupported = "불가능"
    }

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
    static let defaultCategoryColorKeys: [String: String] = [
        "업무": "brown",
        "개발": "blue",
        "공부": "lime",
        "조사": "teal",
        "소통": "orange",
        "엔터": "red",
        "기록": "sky",
        "기타": "gray",
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
        CategoryDefinition(defaultName: "업무", name: "업무", emoji: "💼", colorKey: "brown"),
        CategoryDefinition(defaultName: "개발", name: "개발", emoji: "💻", colorKey: "blue"),
        CategoryDefinition(defaultName: "공부", name: "공부", emoji: "📚", colorKey: "lime"),
        CategoryDefinition(defaultName: "조사", name: "조사", emoji: "🔎", colorKey: "teal"),
        CategoryDefinition(defaultName: "기록", name: "기록", emoji: "📓", colorKey: "sky"),
        CategoryDefinition(defaultName: "소통", name: "소통", emoji: "💬", colorKey: "orange"),
        CategoryDefinition(defaultName: "엔터", name: "엔터", emoji: "🎬", colorKey: "red"),
        CategoryDefinition(defaultName: "기타", name: "기타", emoji: "📦", colorKey: "gray"),
    ]

    static func categoryName(_ defaultName: String) -> String {
        CategoryStore.shared.displayName(forDefaultName: defaultName)
    }

    static func defaultName(forCategory category: String) -> String {
        CategoryStore.shared.defaultName(forDisplayName: category)
    }

    static func categoryEmoji(for category: String) -> String {
        if isProductivityManagementCategory(category) {
            return productivityManagementAppEmoji
        }
        return CategoryStore.shared.emoji(for: category)
    }

    static func categoryColor(for category: String) -> Color {
        if isProductivityManagementCategory(category) {
            return CategoryColorPalette.color(for: "gray")
        }
        return CategoryColorPalette.color(for: CategoryStore.shared.colorKey(for: category))
    }

    enum UnmappedAppHandling: String, CaseIterable, Identifiable {
        case pendingClassification
        case recordAsOther
        case doNotRecord

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pendingClassification: return "분류 대기"
            case .recordAsOther: return "기타로 기록"
            case .doNotRecord: return "기록 안 함"
            }
        }

        var subtitle: String {
            switch self {
            case .pendingClassification:
                return "미분류 목록에 모아 나중에 분류합니다."
            case .recordAsOther:
                return "기타로 기록하며 미분류 목록에는 추가하지 않습니다."
            case .doNotRecord:
                return "등록하지 않은 앱의 사용 시간을 저장하지 않습니다."
            }
        }
    }

    static let defaultUnmappedAppHandling: UnmappedAppHandling = .pendingClassification

    static func storedUnmappedAppHandling(
        in defaults: UserDefaults = .standard
    ) -> UnmappedAppHandling {
        guard let rawValue = defaults.string(
            forKey: AppStorageKey.unmappedAppHandling
        ) else {
            return defaultUnmappedAppHandling
        }
        return UnmappedAppHandling(rawValue: rawValue)
            ?? defaultUnmappedAppHandling
    }

    // MARK: - 브라우저 bundle identifier (URL 기반 분류용)
    static let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.kagi.kagimacOS",
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
        // ⏰ 생산성 관리
        (horongHorongBundleIdentifier, "호롱호롱", productivityManagementAppCategory),
        ("com.apple.reminders", "미리알림", productivityManagementAppCategory),

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

        // 💬 소통
        ("com.kakao.KakaoTalkMac", "카카오톡", categoryName("소통")),
        ("com.hnc.Discord", "Discord", categoryName("소통")),
    ] }

    // MARK: - 기본 웹사이트→카테고리 매핑
    static var defaultWebsiteCategoryRules: [
        (domain: String, aliases: [String], category: String)
    ] { [
        ("chatgpt.com", [], categoryName("개발")),
        ("claude.ai", [], categoryName("개발")),
        ("gemini.google.com", [], categoryName("개발")),
        ("youtube.com", ["youtu.be"], categoryName("엔터")),
        ("netflix.com", [], categoryName("엔터")),
    ] }

    static func websiteAliases(for domain: String) -> [String] {
        guard let normalizedDomain = WebsiteCategoryRule.normalizedDomain(from: domain) else {
            return []
        }
        return defaultWebsiteCategoryRules.first {
            $0.domain == normalizedDomain
        }?.aliases ?? []
    }

    static func canonicalWebsiteRuleDomain(for domain: String) -> String {
        guard let normalizedDomain = WebsiteCategoryRule.normalizedDomain(from: domain) else {
            return domain
        }
        return defaultWebsiteCategoryRules.first {
            $0.domain == normalizedDomain || $0.aliases.contains(normalizedDomain)
        }?.domain ?? normalizedDomain
    }

    static func websiteRuleDomains(for domain: String) -> [String] {
        let canonicalDomain = canonicalWebsiteRuleDomain(for: domain)
        return [canonicalDomain] + websiteAliases(for: canonicalDomain)
    }

    static func legacyWebsiteTrackedBundleSuffixes(for domain: String) -> [String] {
        switch canonicalWebsiteRuleDomain(for: domain) {
        case "youtube.com":
            return [".youtube"]
        case "netflix.com":
            return [".netflix"]
        default:
            return []
        }
    }

    static var allDefaultCategoryRules: [
        (bundleId: String, appName: String, category: String)
    ] {
        defaultCategoryRules + defaultWebsiteCategoryRules.map { rule in
            (
                bundleId: WebsiteCategoryRule.bundleIdentifier(for: rule.domain),
                appName: rule.domain,
                category: rule.category
            )
        }
    }

    // MARK: - 모든 카테고리 목록
    static var allCategories: [String] { CategoryStore.shared.categoryNames }

    static func defaultCategoryRule(
        for bundleIdentifier: String,
        includingHidden: Bool = false
    ) -> (bundleId: String, appName: String, category: String)? {
        guard includingHidden || !isDefaultCategoryRuleHidden(bundleIdentifier) else { return nil }
        return allDefaultCategoryRules.first { $0.bundleId == bundleIdentifier }
    }

    static func isDefaultCategoryRuleHidden(_ bundleIdentifier: String) -> Bool {
        hiddenDefaultCategoryRuleBundleIDs.contains(bundleIdentifier)
    }

    static func hideDefaultCategoryRule(_ bundleIdentifier: String) {
        var ids = hiddenDefaultCategoryRuleBundleIDs
        ids.insert(bundleIdentifier)
        saveHiddenDefaultCategoryRuleBundleIDs(ids)
    }

    static func restoreDefaultCategoryRule(_ bundleIdentifier: String) {
        var ids = hiddenDefaultCategoryRuleBundleIDs
        ids.remove(bundleIdentifier)
        saveHiddenDefaultCategoryRuleBundleIDs(ids)
    }

    private static var hiddenDefaultCategoryRuleBundleIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: AppStorageKey.hiddenDefaultCategoryRuleBundleIDs) ?? [])
    }

    private static func saveHiddenDefaultCategoryRuleBundleIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: AppStorageKey.hiddenDefaultCategoryRuleBundleIDs)
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
    static let defaultPomodoroReflectionEnabled = false
    static let defaultTimerCompletionNotificationStyle: TimerCompletionNotificationStyle = .system
    static let defaultTodayPlanningReminderEnabled = false
    static let defaultTodayPlanningReminderDelayMinutes = 5
    static let todayPlanningReminderDelayMinutesRange = 1...60
    static let defaultPomodoroBreakMinutes = 5
    static let defaultLongFocusFocusMinutes = 100
    static let defaultLongFocusBreakMinutes = 10
    static let defaultCustomFocusMinutes = 60
    static let defaultCustomBreakMinutes = 10
    static let defaultPostBreakTransitionPromptDelayMinutes = 10
    static let timerCompletionNativeReflectionDelaySeconds: TimeInterval = 4
    static let todayPlanningReminderNotificationIdentifier = "app.horonghorong.todayPlanningReminder"

    enum TimerCompletionNotificationStyle: String, CaseIterable, Identifiable {
        case system
        case horong

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "macOS 알림"
            case .horong: return "호롱호롱 알림"
            }
        }

        var subtitle: String {
            switch self {
            case .system:
                return "알림 센터에 남아 놓친 알림도 다시 확인할 수 있어요."
            case .horong:
                return "화면 오른쪽 위에 더 또렷한 강조 스타일로 잠시 표시돼요."
            }
        }
    }

    struct TimerCompletionNotificationContent: Equatable {
        let title: String
        let subtitle: String
        let body: String
    }

    static func focusCompletionNotificationContent(
        focusMinutes: Int
    ) -> TimerCompletionNotificationContent {
        TimerCompletionNotificationContent(
            title: "포모도로 완료",
            subtitle: "\(focusMinutes)분 집중 완료",
            body: "집중 기록을 저장했어요. 잠시 쉬어가세요."
        )
    }

    static let breakCompletionNotificationContent = TimerCompletionNotificationContent(
        title: "휴식 끝!",
        subtitle: "다시 집중할 준비가 되셨나요?",
        body: "준비되었다면 다음 포모도로를 시작해 보세요."
    )

    static func todayPlanningReminderDelaySeconds(for minutes: Int) -> TimeInterval {
        let normalizedMinutes = min(
            max(minutes, todayPlanningReminderDelayMinutesRange.lowerBound),
            todayPlanningReminderDelayMinutesRange.upperBound
        )
        return TimeInterval(normalizedMinutes * 60)
    }

    static var postBreakProductiveCategories: Set<String> {
        Set(["업무", "개발", "공부", "조사", "기록"].map { categoryName($0) })
    }

    enum PostBreakTransitionPromptMode: String, CaseIterable, Identifiable {
        case afterDelay
        case always

        var id: String { rawValue }

        var label: String {
            switch self {
            case .afterDelay: return "필요할 때만"
            case .always: return "항상 묻기"
            }
        }

        var subtitle: String {
            switch self {
            case .afterDelay:
                return "휴식 후 포모도로나 업무성 카테고리 복귀가 없을 때만 묻습니다."
            case .always:
                return "휴식이 끝나면 바로 다음 흐름을 묻습니다."
            }
        }
    }

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
            let v = defaults.integer(forKey: AppStorageKey.customFocusMinutes)
            return v > 0 ? v : defaultCustomFocusMinutes
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
            let v = defaults.integer(forKey: AppStorageKey.customBreakMinutes)
            return v > 0 ? v : defaultCustomBreakMinutes
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
    static let popoverWidth: CGFloat = 360
    static let popoverMaxHeight: CGFloat = 560

    // MARK: - 퀵 메모 패널 크기
    static let quickMemoPanelWidth: CGFloat = 616
    static let quickMemoPanelHeight: CGFloat = 360
    static let quickMemoPanelMinHeight: CGFloat = 160
    static let quickMemoPanelMaxHeight: CGFloat = 360

    // MARK: - 통계 윈도우 크기
    static let statsWindowWidth: CGFloat = 880
    static let statsWindowHeight: CGFloat = 660

    // MARK: - 메모 윈도우 크기
    static let memoBrowserWindowWidth: CGFloat = 1012
    static let memoBrowserWindowHeight: CGFloat = 658

    // MARK: - Agent 실험 설정
    static var defaultAgentRootDirectoryPath: String {
        repositoryRelativePath("Agents", "experiments")
    }
    static let agentIdeaDirectoryName = "ideas"
    static let agentOutputDirectoryName = "outputs"
    // 기본 관심 키워드 = 빈 문자열. 사용자가 직접 등록한 키워드만 사용한다는 정책.
    static let defaultInterestKeywords = ""
    static let defaultAgentType = "Codex"
    static let defaultPlanDayCount = 5
    static let availableAgentTypes = ["Codex", "Claude", "Antigravity", "Opencode", "Gemini"]
    static let maxRepresentativeAgentCount = 3
    static let defaultRepresentativeAgentTypes = ["Codex", "Claude", "Antigravity"]
    static let defaultRepresentativeAgentTypesCSV = defaultRepresentativeAgentTypes.joined(separator: ",")

    static func normalizedRepresentativeAgentTypes(from rawValue: String) -> [String] {
        let candidates = rawValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var normalized: [String] = []
        for agent in candidates where availableAgentTypes.contains(agent) && !normalized.contains(agent) {
            normalized.append(agent)
            if normalized.count == maxRepresentativeAgentCount {
                break
            }
        }

        return normalized.isEmpty ? defaultRepresentativeAgentTypes : normalized
    }

    // MARK: - 루미롱 컴패니언
    static let defaultCompanionEnabled = false
    static let defaultCompanionIdentifier = "hororong"
    static let defaultCompanionHideDuringFocus = true
    static let defaultCompanionBriefingEnabled = true
    static let defaultCompanionBriefingHour = 9
    static let defaultCompanionBriefingMinute = 30
    /// 스프라이트 원본(192×208) 의 절반. 화면에서 부담스럽지 않은 크기.
    static let companionSpriteSize = CGSize(width: 96, height: 104)
    /// 말풍선까지 담는 오버레이 창 크기. 스프라이트는 하단 중앙에 놓인다.
    static let companionOverlaySize = CGSize(width: 300, height: 216)
    /// 대화 모드에서 위로 늘어난 오버레이 창 크기. 스프라이트 위치는 그대로 두고 위쪽만 커진다.
    static let companionChatOverlaySize = CGSize(width: 340, height: 440)
    /// 대화에 쓸 모델 공급자.
    enum CompanionChatProviderKind: String, CaseIterable, Identifiable {
        case appleFoundation
        case ollama

        var id: String { rawValue }

        var label: String {
            switch self {
            case .appleFoundation: return "Apple 온디바이스"
            case .ollama:          return "Ollama"
            }
        }

        var detail: String {
            switch self {
            case .appleFoundation:
                return "설치가 필요 없지만 모델이 작아 긴 지시를 잘 못 지킵니다."
            case .ollama:
                return "Ollama 를 설치하고 모델을 받아야 합니다. 더 큰 모델을 쓸 수 있습니다."
            }
        }
    }

    static let defaultCompanionChatProvider = CompanionChatProviderKind.appleFoundation.rawValue
    /// 뉴스 기능과 같은 엔드포인트를 쓴다.
    static let defaultCompanionOllamaModel = "gemma4:e4b"

    /// 마우스로 지정할 수 있는 활동 영역의 최소 크기. 이보다 작게 그리면 취소로 본다.
    static let companionMinimumRegionSize = CGSize(width: 160, height: 120)
    /// 걷는 속도(pt/초).
    static let companionWalkSpeed: CGFloat = 42
    /// 컴패니언에게 넘길 사용자 메모 길이 상한. 온디바이스 모델의 짧은 컨텍스트를 지키기 위한 값이다.
    static let companionUserNoteMaxLength = 300
    static let companionUserNicknameMaxLength = 20

    enum AppStorageKey {
        static let appearanceMode = "appearance.mode"  // "light" | "dark"
        static let popoverTheme = "appearance.popoverTheme"
        static let agentRootDirectoryPath = "agent.rootDirectoryPath"
        static let ideaDirectoryPath = "agent.ideaDirectoryPath"
        static let outputDirectoryPath = "agent.outputDirectoryPath"
        static let interestKeywords = "agent.interestKeywords"
        static let selectedAgentType = "agent.selectedAgentType"
        static let representativeAgentTypes = "agent.representativeAgentTypes"
        static let planDayCount = "agent.planDayCount"
        static let selectedFocusCategory = "timer.selectedFocusCategory"
        static let pomodoroFocusMinutes = "timer.pomodoroFocusMinutes"
        static let pomodoroBreakMinutes = "timer.pomodoroBreakMinutes"
        static let pomodoroReflectionEnabled = "timer.pomodoroReflectionEnabled"
        static let timerCompletionNotificationStyle = "timer.completionNotificationStyle"
        static let todayPlanningReminderEnabled = "timer.todayPlanningReminderEnabled"
        static let todayPlanningReminderDelayMinutes = "timer.todayPlanningReminderDelayMinutes"
        static let todayPlanningReminderLastPromptDay = "timer.todayPlanningReminderLastPromptDay"
        static let longFocusFocusMinutes = "timer.longFocusFocusMinutes"
        static let longFocusBreakMinutes = "timer.longFocusBreakMinutes"
        static let customFocusMinutes = "timer.customFocusMinutes"
        static let customBreakMinutes = "timer.customBreakMinutes"
        static let postBreakTransitionPromptMode = "timer.postBreakTransitionPromptMode"
        static let postBreakTransitionPromptDelayMinutes = "timer.postBreakTransitionPromptDelayMinutes"
        static let timelineStartHour = "timeline.startHour"
        static let timelineEndHour = "timeline.endHour"
        static let timelineBucketMinutes = "timeline.bucketMinutes"
        static let achievementSuggestionCount = "achievement.suggestionCount"
        static let achievementSuggestionMaxTodoCount = "achievement.suggestionMaxTodoCount"
        static let achievementMonthlySuggestionMinWeeklyGoalCount = "achievement.monthlySuggestionMinWeeklyGoalCount"
        static let achievementMonthlySuggestionCount = "achievement.monthlySuggestionCount"
        static let achievementSuggestionExcludedMemoIcons = "achievement.suggestionExcludedMemoIcons"
        static let achievementDismissedSuggestionKeys = "achievement.dismissedSuggestionKeys"
        static let achievementJourneyMaxFlagCount = "achievement.journeyMaxFlagCount"
        static let achievementJourneyFlagSelections = "achievement.journeyFlagSelections"
        static let achievementVisionOrder = "achievement.visionOrder"
        static let menubarLabelStyle = "menubar.labelStyle"
        static let menubarTimeStyle = "menubar.timeStyle"
        static let menubarIcon = "menubar.icon"
        static let anonymousTelemetryEnabled = "telemetry.anonymousEnabled"
        static let anonymousTelemetryPrompted = "telemetry.anonymousPrompted"
        static let anonymousInstallId = "telemetry.anonymousInstallId"
        static let remindersImportEnabled = "memo.remindersImportEnabled"
        static let remindersImportSelectedCalendarIDs = "memo.remindersImportSelectedCalendarIDs"
        static let hiddenDefaultCategoryRuleBundleIDs = "category.hiddenDefaultRuleBundleIDs"
        static let unmappedAppHandling = "category.unmappedAppHandling"
        static let companionEnabled = "companion.enabled"
        static let companionSelectedIdentifier = "companion.selectedIdentifier"
        static let companionRoamingRegion = "companion.roamingRegion"
        static let companionHideDuringFocus = "companion.hideDuringFocus"
        static let companionBriefingEnabled = "companion.briefingEnabled"
        static let companionBriefingHour = "companion.briefingHour"
        static let companionBriefingMinute = "companion.briefingMinute"
        static let companionBriefingLastDeliveredAt = "companion.briefingLastDeliveredAt"
        static let companionUserNickname = "companion.userNickname"
        static let companionUserNote = "companion.userNote"
        static let companionOnboardingSeen = "companion.onboardingSeen"
        static let companionChatProvider = "companion.chatProvider"
        static let companionOllamaModel = "companion.ollamaModel"
    }

    // MARK: - 메뉴바 표시 형식
    enum MenubarLabelStyle: String, CaseIterable, Identifiable {
        case timeAndIcon
        case timeOnly
        case categoryOnly
        case iconOnly

        var id: String { rawValue }
        var label: String {
            switch self {
            case .timeAndIcon:  return "시간 + 이모지"
            case .timeOnly:     return "시간만"
            case .categoryOnly: return "카테고리"
            case .iconOnly:     return "아이콘만"
            }
        }
    }

    enum MenubarTimeStyle: String, CaseIterable, Identifiable {
        case mmss
        case minutes

        var id: String { rawValue }
        var label: String {
            switch self {
            case .mmss:    return "분:초 (25:00)"
            case .minutes: return "분 (25분)"
            }
        }
    }

    static let defaultMenubarLabelStyle = MenubarLabelStyle.timeAndIcon.rawValue
    static let defaultMenubarTimeStyle = MenubarTimeStyle.mmss.rawValue

    // MARK: - 메뉴바 아이콘 (idle 상태에서 표시되는 대표 아이콘)
    enum MenubarIconStyle: String, CaseIterable, Identifiable {
        case horong = "MenuBarIcon"
        case horong2 = "MenuBarIcon2"
        case horong3 = "MenuBarIcon3"

        var id: String { rawValue }

        /// Assets.xcassets 의 imageset 이름.
        var imageName: String { rawValue }

        var label: String {
            switch self {
            case .horong:  return "호롱불"
            case .horong2: return "호롱불 2"
            case .horong3: return "호롱불 3"
            }
        }
    }

    static let defaultMenubarIcon = MenubarIconStyle.horong.rawValue

    // MARK: - 타임라인 표시 기본값
    static let defaultTimelineStartHour = 0
    static let defaultTimelineEndHour = 24
    static let defaultTimelineBucketMinutes = 30
    static let timelineBucketMinuteOptions: [Int] = [10, 15, 20, 30, 45, 60, 90, 120]

    // MARK: - 성취 추천 기본값
    static let defaultAchievementSuggestionCount = 4
    static let defaultAchievementSuggestionMaxTodoCount = 5
    static let defaultAchievementMonthlySuggestionMinWeeklyGoalCount = 3
    static let defaultAchievementMonthlySuggestionCount = 2
    static let legacyAchievementSuggestionExcludedMemoIconsRaw = "☕️,💡,📜"
    static let defaultAchievementSuggestionExcludedMemoIcons = ["☕️", "🌱", "📜"]
    static let defaultAchievementSuggestionExcludedMemoIconsRaw = defaultAchievementSuggestionExcludedMemoIcons.joined(separator: ",")
    static let achievementSuggestionCountRange = 1...8
    static let achievementSuggestionMaxTodoCountRange = 2...12
    static let achievementMonthlySuggestionMinWeeklyGoalCountRange = 2...8
    static let achievementMonthlySuggestionCountRange = 1...6
    static let defaultAchievementJourneyMaxFlagCount = 5
    static let achievementJourneyMaxFlagCountRange = 1...8
    /// 비전 선택 목록의 행 높이·간격. 드래그 재정렬이 이동 거리를 계산할 때 함께 쓴다.
    static let achievementVisionRowHeight: CGFloat = 34
    static let achievementVisionRowSpacing: CGFloat = 8

    // MARK: - 뉴스 큐레이션 설정
    static var defaultNewsRunnerPath: String {
        newsRunnerPath() ?? ""
    }
    static var defaultNewsDataBasePath: String {
        newsDataBasePath()
    }
    static let newsRunnerMissingMessage = "뉴스 리포트 실행 파일을 찾을 수 없습니다. 앱을 다시 설치한 뒤에도 문제가 계속되면 개발자에게 문의해주세요."
    static let defaultNewsProvider = "codex"
    static var defaultNewsOllamaModel: String {
        recommendedNewsOllamaModel()
    }
    static let defaultNewsOllamaEndpoint = "http://localhost:11434"
    static let defaultNewsOllamaTimeout = 120.0
    static var newsHardwareMemoryGB: Int {
        memoryGB(forPhysicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }
    static func recommendedNewsOllamaModel(physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        newsOllamaRecommendationKinds(physicalMemoryBytes: physicalMemoryBytes)
            .first { $0.value == .primary }?
            .key ?? "qwen3:1.7b"
    }
    static func newsOllamaRecommendationKinds(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> [String: NewsOllamaRecommendationKind] {
        let memoryGB = memoryGB(forPhysicalMemoryBytes: physicalMemoryBytes)
        switch memoryGB {
        case 64...:
            return [
                "qwen3:32b": .primary,
                "qwen3:14b": .lightweight,
                "gpt-oss:120b": .quality,
            ]
        case 48..<64:
            return [
                "qwen3:30b": .primary,
                "qwen3:14b": .lightweight,
                "qwen3:32b": .quality,
                "gpt-oss:120b": .caution,
            ]
        case 24..<48:
            return [
                "qwen3:14b": .primary,
                "qwen3:8b": .lightweight,
                "gemma4:26b": .quality,
                "gpt-oss:20b": .caution,
                "qwen3:30b": .unsupported,
                "qwen3:32b": .unsupported,
                "gemma4:31b": .unsupported,
                "gpt-oss:120b": .unsupported,
            ]
        case 16..<24:
            return [
                "qwen3:8b": .primary,
                "qwen3:4b": .lightweight,
                "qwen3:14b": .quality,
                "gemma4:26b": .caution,
                "qwen3:30b": .unsupported,
                "qwen3:32b": .unsupported,
                "gemma4:31b": .unsupported,
                "gpt-oss:120b": .unsupported,
            ]
        case 12..<16:
            return [
                "qwen3:4b": .primary,
                "qwen3:1.7b": .lightweight,
                "qwen3:8b": .quality,
                "qwen3:14b": .caution,
                "qwen3:30b": .unsupported,
                "qwen3:32b": .unsupported,
                "gemma4:26b": .unsupported,
                "gemma4:31b": .unsupported,
                "gpt-oss:20b": .unsupported,
                "gpt-oss:120b": .unsupported,
            ]
        default:
            return [
                "qwen3:1.7b": .primary,
                "qwen3:4b": .caution,
                "qwen3:8b": .unsupported,
                "qwen3:14b": .unsupported,
                "qwen3:30b": .unsupported,
                "qwen3:32b": .unsupported,
                "gemma4:26b": .unsupported,
                "gemma4:31b": .unsupported,
                "gpt-oss:20b": .unsupported,
                "gpt-oss:120b": .unsupported,
            ]
        }
    }
    private static func memoryGB(forPhysicalMemoryBytes bytes: UInt64) -> Int {
        let gib = UInt64(1024 * 1024 * 1024)
        return Int((bytes + gib - 1) / gib)
    }
    static let availableNewsOllamaModelOptions: [NewsOllamaModelOption] = [
        NewsOllamaModelOption(
            name: "qwen3:1.7b",
            label: "Qwen3 1.7B",
            detail: "장점: 매우 가볍고 빠른 저사양 테스트용. 품질보다 실행 가능성 확인에 적합. 권장 RAM: 8GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3:4b",
            label: "Qwen3 4B",
            detail: "장점: 가볍지만 생각보다 준수한 추론이 가능해 빠른 실험에 좋음. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3:8b",
            label: "Qwen3 8B",
            detail: "장점: 속도와 품질 균형이 좋아 저부하 뉴스 요약 후보로 적합. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3:14b",
            label: "Qwen3 14B",
            detail: "장점: 한국어/영어 판단과 구조화 출력 균형이 좋아 뉴스 큐레이션 1차 추천. 권장 RAM: 24GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3:30b",
            label: "Qwen3 30B",
            detail: "장점: MoE 계열로 큰 모델 대비 효율적인 고품질 비교 후보. 권장 RAM: 48GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3:32b",
            label: "Qwen3 32B",
            detail: "장점: Qwen dense 대형 후보로 깊은 분석 품질 비교에 적합. 권장 RAM: 48GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "gemma4:e2b",
            label: "Gemma 4 E2B",
            detail: "장점: 가장 가볍고 빠른 테스트용. 빠른 반복에 좋지만 분석 깊이는 제한적. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "gemma4:e4b",
            label: "Gemma 4 E4B",
            detail: "장점: 속도와 품질 균형이 좋은 가벼운 실험용. 짧은 리포트에 적합. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "gemma4:26b",
            label: "Gemma 4 26B",
            detail: "장점: MoE 계열로 큰 모델 대비 효율적인 품질 비교 후보. 긴 리포트는 속도 확인 필요. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "gemma4:31b",
            label: "Gemma 4 31B",
            detail: "장점: Gemma 후보 중 고품질 비교용. 24GB 환경에서는 부담이 클 수 있음. 권장 RAM: 48GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "gpt-oss:20b",
            label: "GPT-OSS 20B",
            detail: "장점: 추론·구조화 출력·도구 사용 성향 비교에 좋음. 뉴스 품질은 eval 검증 필요. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "gpt-oss:120b",
            label: "GPT-OSS 120B",
            detail: "장점: 대형 추론 모델 기준점으로 활용 가능. 일반 노트북 로컬 실행에는 매우 무거움. 권장 RAM: 128GB+.",
            availability: .local,
            isRecommended: false
        ),
    ]
    static var availableNewsOllamaModels: [String] {
        availableNewsOllamaModelOptions.map(\.name)
    }
    // 기본 뉴스 키워드 = 빈 문자열. 사용자가 관심사를 직접 등록하기 전까지 자동 키워드는 넣지 않는다.
    static let defaultNewsInterestKeywords = ""
    static let availableNewsProviders = ["ollama", "codex", "claude", "antigravity", "opencode", "gemini"]
    enum NewsStorageKey {
        static let dataBasePath = "news.dataBasePath"
        static let selectedProvider = "news.selectedProvider"
        static let ollamaModel = "news.ollama.model"
        static let ollamaEndpoint = "news.ollama.endpoint"
        static let ollamaTimeout = "news.ollama.timeout"
        static let interestKeywords = "news.interestKeywords"
        static let youtubeChannelIds = "news.youtube.channelIds"  // legacy CSV, NewsSourceStore 가 마이그레이션
        static let sources = "news.sources.v1"
        static let schedule = "news.schedule"
        static let maxItemsPerSource = "news.maxItemsPerSource"
    }

    static let defaultNewsMaxItemsPerSource = 10

    enum PopoverTheme: String, CaseIterable, Identifiable {
        case warmLantern
        case wineLantern
        case gamePixel

        var id: String { rawValue }

        var label: String {
            switch self {
            case .warmLantern: return "따뜻한 등불"
            case .wineLantern: return "와인 랜턴"
            case .gamePixel: return "게임 픽셀"
            }
        }

        var symbol: String {
            switch self {
            case .warmLantern: return "🏮"
            case .wineLantern: return "🍷"
            case .gamePixel: return "▣"
            }
        }

        static func normalized(rawValue: String) -> Self {
            Self(rawValue: rawValue) ?? .warmLantern
        }
    }

    static let defaultAppearanceMode = "light"
    static let defaultPopoverTheme = PopoverTheme.warmLantern.rawValue

    static let availableNewsSchedules: [(value: String, label: String)] = [
        ("manual", "수동"),
        ("hourly", "매시간"),
        ("daily", "매일"),
    ]
    static let defaultNewsSchedule = "manual"

    static func agentIdeaDirectoryPath(for rootDirectoryPath: String) -> String {
        appendPath(rootDirectoryPath, agentIdeaDirectoryName)
    }

    static func agentOutputDirectoryPath(for rootDirectoryPath: String) -> String {
        appendPath(rootDirectoryPath, agentOutputDirectoryName)
    }

    static func newsRunnerPath(
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        repositoryRootPath: String? = Constants.repositoryRootPath,
        fileManager: FileManager = .default
    ) -> String? {
        let bundleCandidates = [
            bundleResourceURL?
                .appendingPathComponent("news_report", isDirectory: true)
                .appendingPathComponent("runner.py", isDirectory: false),
            bundleResourceURL?
                .appendingPathComponent("Agents", isDirectory: true)
                .appendingPathComponent("news_report", isDirectory: true)
                .appendingPathComponent("runner.py", isDirectory: false),
        ]
        let repositoryCandidate = repositoryRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("Agents", isDirectory: true)
                .appendingPathComponent("news_report", isDirectory: true)
                .appendingPathComponent("runner.py", isDirectory: false)
        }

        return ([repositoryCandidate] + bundleCandidates)
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.path) }?
            .path
    }

    static func newsDataBasePath(
        repositoryRootPath: String? = Constants.repositoryRootPath,
        applicationSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first,
        fileManager: FileManager = .default
    ) -> String {
        if let repositoryRootPath {
            let repositoryNewsPath = URL(fileURLWithPath: repositoryRootPath, isDirectory: true)
                .appendingPathComponent("Agents", isDirectory: true)
                .appendingPathComponent("news_report", isDirectory: true)
            if fileManager.fileExists(atPath: repositoryNewsPath.path) {
                return repositoryNewsPath.path
            }
        }

        guard let applicationSupportDirectory else { return "" }
        return applicationSupportDirectory
            .appendingPathComponent(SwiftDataStoreLocation.directoryName, isDirectory: true)
            .appendingPathComponent("news_report", isDirectory: true)
            .path
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
    var colorKey: String?
}

struct CategoryColorOption: Identifiable {
    let key: String
    let name: String
    let color: Color
    var id: String { key }
}

/// 카테고리마다 하나의 고유 색상 키를 유지한다.
/// 준비된 팔레트를 먼저 쓰고, 모두 사용하면 안정적인 자동 색상 키를 순서대로 생성한다.
enum CategoryColorPalette {
    static let fallbackKey = "gray"
    static let options: [CategoryColorOption] = [
        CategoryColorOption(key: "brown", name: "갈색", color: .brown),
        CategoryColorOption(key: "blue", name: "파랑", color: .blue),
        CategoryColorOption(
            key: "lime",
            name: "연두",
            color: Color(red: 0.65, green: 0.87, blue: 0.35)
        ),
        CategoryColorOption(key: "teal", name: "청록", color: .teal),
        CategoryColorOption(key: "orange", name: "주황", color: .orange),
        CategoryColorOption(key: "red", name: "빨강", color: .red),
        CategoryColorOption(
            key: "sky",
            name: "하늘",
            color: Color(red: 0.53, green: 0.81, blue: 0.92)
        ),
        CategoryColorOption(key: "gray", name: "회색", color: .gray),
        CategoryColorOption(key: "indigo", name: "남색", color: .indigo),
        CategoryColorOption(key: "mint", name: "민트", color: .mint),
        CategoryColorOption(key: "cyan", name: "시안", color: .cyan),
        CategoryColorOption(key: "green", name: "초록", color: .green),
        CategoryColorOption(key: "yellow", name: "노랑", color: .yellow),
        CategoryColorOption(key: "pink", name: "분홍", color: .pink),
        CategoryColorOption(key: "purple", name: "보라", color: .purple),
    ]

    static func color(for key: String?) -> Color {
        if let option = options.first(where: { $0.key == key }) {
            return option.color
        }
        guard let index = generatedIndex(for: key) else {
            return options.first(where: { $0.key == fallbackKey })?.color ?? .gray
        }
        let hue = (Double(index) * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1)
        let saturation = 0.58 + (Double(index % 3) * 0.08)
        let brightness = 0.72 + (Double(index % 2) * 0.12)
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    static func option(for key: String) -> CategoryColorOption? {
        if let option = options.first(where: { $0.key == key }) {
            return option
        }
        guard let index = generatedIndex(for: key) else { return nil }
        return CategoryColorOption(
            key: key,
            name: "자동 색상 \(index + 1)",
            color: color(for: key)
        )
    }

    static func isSupported(_ key: String) -> Bool {
        options.contains { $0.key == key } || generatedIndex(for: key) != nil
    }

    static func nextAvailableKey(usedKeys: Set<String>) -> String {
        if let option = options.first(where: { !usedKeys.contains($0.key) }) {
            return option.key
        }
        var index = 0
        while usedKeys.contains(generatedKey(index: index)) {
            index += 1
        }
        return generatedKey(index: index)
    }

    static func isGenerated(_ key: String) -> Bool {
        generatedIndex(for: key) != nil
    }

    private static func generatedKey(index: Int) -> String {
        "generated-\(index)"
    }

    private static func generatedIndex(for key: String?) -> Int? {
        guard let key, key.hasPrefix("generated-"),
              let index = Int(key.dropFirst("generated-".count)),
              index >= 0 else {
            return nil
        }
        return index
    }
}

@Observable
final class CategoryStore: @unchecked Sendable {
    static let shared = CategoryStore()

    private let storageKey: String
    private let userDefaults: UserDefaults
    private(set) var categories: [CategoryDefinition] = []

    var categoryNames: [String] {
        categories.map(\.name)
    }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "categories.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
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

    func colorKey(for category: String) -> String {
        categories.first { $0.name == category }?.colorKey
            ?? Constants.defaultCategoryColorKeys[defaultName(forDisplayName: category)]
            ?? CategoryColorPalette.fallbackKey
    }

    func canDelete(_ category: String) -> Bool {
        defaultName(forDisplayName: category) != "기타"
    }

    func add(name: String, emoji: String) -> Bool {
        let trimmed = normalizedName(name)
        guard !trimmed.isEmpty, !categoryNames.contains(trimmed) else { return false }
        let colorKey = CategoryColorPalette.nextAvailableKey(
            usedKeys: Set(categories.compactMap(\.colorKey))
        )
        categories.append(
            CategoryDefinition(
                defaultName: trimmed,
                name: trimmed,
                emoji: normalizedEmoji(emoji),
                colorKey: colorKey
            )
        )
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

    /// 이미 사용 중인 색을 선택하면 두 카테고리의 색을 교환해 1:1 매핑을 유지한다.
    func setColorKey(_ colorKey: String, for category: String) -> Bool {
        guard CategoryColorPalette.isSupported(colorKey),
              let targetIndex = categories.firstIndex(where: { $0.name == category }) else {
            return false
        }
        let previousColorKey = categories[targetIndex].colorKey
        guard previousColorKey != colorKey else { return true }

        if let ownerIndex = categories.firstIndex(where: { $0.colorKey == colorKey }),
           ownerIndex != targetIndex {
            categories[ownerIndex].colorKey = previousColorKey
        }
        categories[targetIndex].colorKey = colorKey
        save()
        return true
    }

    func delete(name: String) {
        guard canDelete(name) else { return }
        categories.removeAll { $0.name == name }
        save()
    }

    private func load() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CategoryDefinition].self, from: data),
           !decoded.isEmpty {
            categories = mergedWithNewDefaults(decoded)
        } else {
            categories = Constants.defaultCategoryDefinitions
        }
        categories = assigningUniqueColors(to: categories)
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

    private func assigningUniqueColors(
        to definitions: [CategoryDefinition]
    ) -> [CategoryDefinition] {
        var result = definitions
        var usedKeys: Set<String> = []

        for index in result.indices {
            let preferredKey = result[index].colorKey
                ?? Constants.defaultCategoryColorKeys[result[index].defaultName]
            if let preferredKey,
               CategoryColorPalette.isSupported(preferredKey),
               !usedKeys.contains(preferredKey) {
                result[index].colorKey = preferredKey
                usedKeys.insert(preferredKey)
            } else {
                let colorKey = CategoryColorPalette.nextAvailableKey(usedKeys: usedKeys)
                result[index].colorKey = colorKey
                usedKeys.insert(colorKey)
            }
        }
        return result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            userDefaults.set(data, forKey: storageKey)
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
