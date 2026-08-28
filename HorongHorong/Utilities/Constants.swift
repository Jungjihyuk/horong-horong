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

    // MARK: - 통합 윈도우 크기
    static let hubWindowWidth: CGFloat = 1080
    static let hubWindowHeight: CGFloat = 700

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
    static let availableAgentTypes = ["Codex", "Claude", "Antigravity", "Opencode", "Hermes"]
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
    static let defaultCompanionEnabled = true
    static let defaultCompanionIdentifier = "hororong"
    static let defaultCompanionHideDuringFocus = true
    static let defaultCompanionBriefingEnabled = true
    static let defaultCompanionBriefingHour = 9
    static let defaultCompanionBriefingMinute = 30
    static let defaultCompanionFocusNudgeEnabled = true
    /// 등록할 수 있는 넛지 문구 전체 길이 상한.
    static let companionFocusNudgeMessagesMaxLength = 500
    static let defaultFocusNudgeDetectionMode = FocusNudgeDetectionMode.ruleBased
    static let defaultFocusNudgeFrequencyMode = FocusNudgeFrequencyMode.limited
    static let defaultFocusNudgeRequiredFeedbackCount = 20
    static let defaultFocusNudgeManualFocusPercent = 60
    static let defaultFocusNudgeManualMaxAppSwitches = 6
    static let defaultFocusNudgeMaximumPerSession = 2
    /// 스프라이트 원본(192×208) 의 절반. 화면에서 부담스럽지 않은 크기.
    static let companionSpriteSize = CGSize(width: 96, height: 104)
    /// 말풍선까지 담는 오버레이 창 크기. 스프라이트는 하단 중앙에 놓인다.
    static let companionOverlaySize = CGSize(width: 300, height: 216)
    /// 대화 모드에서 위로 늘어난 오버레이 창 크기. 스프라이트 위치는 그대로 두고 위쪽만 커진다.
    static let companionChatOverlaySize = CGSize(width: 340, height: 440)

    /// 말풍선 크기. 할일이 많은 날에는 기본 크기로 다 안 보여서 사용자가 골라 키울 수 있게 한다.
    enum CompanionBubbleSize: String, CaseIterable, Identifiable {
        case compact
        case regular
        case large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: return "작게"
            case .regular: return "보통"
            case .large:   return "크게"
            }
        }

        /// 스프라이트 위로 말풍선이 쓸 수 있는 최대 높이.
        var bubbleMaxHeight: CGFloat {
            switch self {
            case .compact: return 150
            case .regular: return 260
            case .large:   return 420
            }
        }

        /// 말풍선이 커진 만큼 오버레이 창도 같이 커져야 잘리지 않는다.
        /// 스프라이트와 여백을 더한 값이다.
        var overlaySize: CGSize {
            CGSize(
                width: self == .large ? 380 : 300,
                height: bubbleMaxHeight + companionSpriteSize.height + 24
            )
        }

        var detail: String {
            switch self {
            case .compact: return "화면을 적게 가립니다. 할일이 많으면 스크롤해서 봅니다."
            case .regular: return "기본값입니다."
            case .large:   return "할일이 많은 날에도 한눈에 보입니다. 화면을 더 가립니다."
            }
        }
    }

    static let defaultCompanionBubbleSize = CompanionBubbleSize.regular.rawValue

    static var resolvedCompanionBubbleSize: CompanionBubbleSize {
        CompanionBubbleSize(
            rawValue: UserDefaults.standard.string(forKey: AppStorageKey.companionBubbleSize) ?? ""
        ) ?? .regular
    }

    /// 위쪽 공간이 필요할 때 쓰는 오버레이 창 크기.
    ///
    /// 대화창은 고정 크기(`companionChatOverlaySize`)를 그대로 써야 레이아웃이 유지되므로,
    /// 말풍선이 그보다 커질 때만 창을 키운다. 창은 투명하고 그려진 곳만 클릭을 받으므로
    /// 필요보다 큰 창이어도 화면을 가리지 않는다.
    static var companionExpandedOverlaySize: CGSize {
        let bubble = resolvedCompanionBubbleSize.overlaySize
        return CGSize(
            width: max(companionChatOverlaySize.width, bubble.width),
            height: max(companionChatOverlaySize.height, bubble.height)
        )
    }
    /// 대화에 쓸 모델 공급자.
    enum CompanionChatProviderKind: String, CaseIterable, Identifiable {
        case appleFoundation
        case mlx
        case ollama

        var id: String { rawValue }

        var label: String {
            switch self {
            case .appleFoundation: return "Apple 온디바이스"
            case .mlx:             return "MLX (앱 내장)"
            case .ollama:          return "Ollama"
            }
        }

        var detail: String {
            switch self {
            case .appleFoundation:
                return "설치가 필요 없지만 모델이 작아 긴 지시를 잘 못 지킵니다."
            case .mlx:
                return "따로 설치할 프로그램이 없습니다. 모델을 한 번만 받아두면 앱이 직접 돌립니다. Apple Silicon 맥 전용."
            case .ollama:
                return "Ollama 를 설치하고 모델을 받아야 합니다. 더 큰 모델을 쓸 수 있습니다."
            }
        }
    }

    /// 앱이 직접 돌리는 MLX 모델 후보. `name` 은 내려받을 HuggingFace 저장소 id 다.
    struct CompanionMLXModelOption: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let label: String
        let detail: String
        let minimumMemoryGB: Int
    }

    /// 모델 가중치가 앱 프로세스 안에 그대로 올라오므로, 항상 떠 있는 컴패니언에는
    /// Ollama 기본값(`gemma4:e4b`)보다 한 단계 가벼운 쪽을 기본으로 둔다.
    static let defaultCompanionMLXModel = "mlx-community/gemma-4-e2b-it-4bit"

    static let availableCompanionMLXModelOptions: [CompanionMLXModelOption] = [
        CompanionMLXModelOption(
            name: "mlx-community/Qwen3-1.7B-4bit",
            label: "Qwen3 1.7B",
            detail: "가장 가볍고 빠릅니다. 메모리가 빠듯하거나 먼저 시험해 볼 때 좋습니다.",
            minimumMemoryGB: 8
        ),
        CompanionMLXModelOption(
            name: "mlx-community/gemma-4-e2b-it-4bit",
            label: "Gemma 4 E2B",
            detail: "가벼우면서 한국어 대화가 자연스럽습니다. 늘 켜 두는 컴패니언에 알맞습니다.",
            minimumMemoryGB: 16
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Qwen3-4B-4bit",
            label: "Qwen3 4B",
            detail: "긴 지시를 더 잘 따릅니다. 대신 메모리를 조금 더 씁니다.",
            minimumMemoryGB: 16
        ),
        CompanionMLXModelOption(
            name: "mlx-community/gemma-4-e4b-it-4bit",
            label: "Gemma 4 E4B",
            detail: "이 중 답이 가장 좋습니다. 메모리가 넉넉한 맥에서 쓰세요.",
            minimumMemoryGB: 24
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Qwen3-8B-4bit",
            label: "Qwen3 8B",
            detail: "긴 지시를 가장 잘 지킵니다. 가중치가 4.6GB라 늘 켜 두면 그만큼 메모리를 계속 씁니다.",
            minimumMemoryGB: 24
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Qwen3.5-9B-4bit",
            label: "Qwen3.5 9B 4bit",
            detail: "Qwen 3.5 아키텍처 기반의 9B 모델입니다. 한국어 성능이 개선되었습니다.",
            minimumMemoryGB: 16
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            label: "Llama 3.1 8B",
            detail: "구조화 출력 및 논리적인 지시 이행에 최고 수준의 성능을 제공합니다.",
            minimumMemoryGB: 16
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
            label: "Mistral Nemo 12B",
            detail: "긴 문맥 이해와 섬세한 대화 뉘앙스 처리에 강점을 보입니다.",
            minimumMemoryGB: 24
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Phi-3.5-mini-instruct-4bit",
            label: "Phi-3.5 Mini",
            detail: "가장 가벼우면서도 똑똑합니다. 메모리를 최소화해야 할 때 좋습니다.",
            minimumMemoryGB: 8
        ),
        CompanionMLXModelOption(
            name: "mlx-community/Solar-10.7B-Instruct-v1.0-4bit",
            label: "Solar 10.7B",
            detail: "한국어와 영어 처리 밸런스가 가장 훌륭하며 논리력이 탁월합니다.",
            minimumMemoryGB: 16
        ),
        CompanionMLXModelOption(
            name: "mlx-community/aya-23-8B-4bit",
            label: "Aya 23 8B",
            detail: "다국어 지원에 완벽히 특화되어 있으며 한국어도 매우 잘 구사합니다.",
            minimumMemoryGB: 16
        ),
    ]

    static func companionMLXModelLabel(for name: String) -> String {
        availableCompanionMLXModelOptions.first { $0.name == name }?.label ?? name
    }

    // MARK: - 성취탭 목표 추천 공급자

    /// 목표 추천에 쓸 모델. 컴패니언과 나누는 이유는 요구하는 능력이 다르기 때문이다.
    /// 대화는 유창함이, 추천은 JSON 스키마 준수와 의미 군집화가 중요하다.
    enum AchievementSuggestionProviderKind: String, CaseIterable {
        /// Apple Foundation Model. 빠르지만 컨텍스트가 약 4k로 좁다.
        case appleFoundation
        /// 앱 안에서 도는 MLX 모델. 느린 대신 컨텍스트가 넓어 할 일을 더 많이 넣을 수 있다.
        case mlx
        /// Ollama 서버. 가중치가 다른 프로세스에 올라가 앱 메모리를 쓰지 않으므로
        /// 앱 안에서는 못 올리는 큰 모델도 쓸 수 있다.
        case ollama
    }

    static let defaultAchievementSuggestionProvider = AchievementSuggestionProviderKind.appleFoundation.rawValue

    /// 컴패니언 기본값(가벼운 gemma-e2b)과 달리 지시 준수가 중요해 Qwen3 4B를 기본으로 둔다.
    static let defaultAchievementSuggestionMLXModel = "mlx-community/Qwen3-4B-4bit"

    /// 뉴스·컴패니언과 같은 Ollama 서버를 쓴다. 설치된 모델은 OllamaModelPicker 가 직접 조회한다.
    static let defaultAchievementSuggestionOllamaModel = "qwen3:14b"

    /// 목표 추천은 버튼을 눌렀을 때만 도는 **온디맨드** 작업이라, 늘 떠 있는 컴패니언과 달리
    /// 큰 모델을 감당할 수 있다. 그래서 목록을 따로 둔다.
    static let availableAchievementMLXModelOptions: [CompanionMLXModelOption] =
        availableCompanionMLXModelOptions + [
            // Ollama 라인업(qwen3:14b)에 대응하는 MLX 빌드.
            // MLX 는 같은 모델을 더 빠르고 메모리 효율적으로 돌리므로 앱 안에서 쓸 값이 있다.
            // 처음 고르면 가중치를 새로 내려받아야 한다.
            CompanionMLXModelOption(
                name: "mlx-community/Qwen3-14B-4bit",
                label: "Qwen3 14B",
                detail: "이 목록에서 지시 준수가 가장 좋습니다. 대신 느리고 메모리를 많이 씁니다.",
                minimumMemoryGB: 32
            ),
            CompanionMLXModelOption(
                name: "mlx-community/Qwen3.5-35B-A3B-4bit",
                label: "Qwen3.5 35B A3B 4bit",
                detail: "매우 뛰어난 추론 성능을 제공합니다. 가중치가 커서 메모리가 넉넉해야 합니다.",
                minimumMemoryGB: 32
            ),
            CompanionMLXModelOption(
                name: "mlx-community/Qwen3.6-27B-4bit",
                label: "Qwen3.6 27B 4bit",
                detail: "Qwen 3.6 27B 4bit 모델. 대형 모델로 넉넉한 메모리가 필요합니다.",
                minimumMemoryGB: 32
            ),
            CompanionMLXModelOption(
                name: "mlx-community/Qwen3.6-35B-A3B-4bit",
                label: "Qwen3.6 35B-A3B 4bit",
                detail: "Qwen 3.6 35B-A3B 4bit 모델. 최고 수준의 품질을 제공하지만 메모리를 많이 씁니다.",
                minimumMemoryGB: 48
            ),
            CompanionMLXModelOption(
                name: "mlx-community/Qwen3.6-27B-6bit",
                label: "Qwen3.6 27B 6bit",
                detail: "Qwen 3.6 27B 6bit 모델. 고품질 텍스트 생성을 위해 더 높은 정밀도를 사용합니다.",
                minimumMemoryGB: 48
            ),
            CompanionMLXModelOption(
                name: "mlx-community/c4ai-command-r-v01-4bit",
                label: "Command R 35B",
                detail: "목표 분석 및 JSON 구조화 등 복잡한 작업 수행에 특화된 최고 수준 모델입니다.",
                minimumMemoryGB: 32
            ),
            CompanionMLXModelOption(
                name: "mlx-community/DeepSeek-V2-Lite-Chat-4bit",
                label: "DeepSeek V2 Lite 16B",
                detail: "논리/수학적 추론이 강점인 MoE 경량 모델입니다.",
                minimumMemoryGB: 24
            ),
            // gemma-4-26b-a4b(MoE)와 gemma-4-31b 는 넣지 않는다.
            // 전자는 mlx-swift-lm 의 Gemma4 구현이 dense 전용이라 MoE 가중치(experts/router)에서
            // unhandledKeys 로 실패하고, 후자는 24GB 맥에서 올리지 못한다. (2026-08-01 확인)
        ]

    /// 프롬프트 문자 예산. 이 이상은 추론이 거부되거나 품질이 떨어진다.
    /// AFM 값은 실측(3,424자 통과 / 5,203자 실패)에 여유를 둔 것이다.
    /// Ollama 실측: 10,815자 주입 시 60초 타임아웃/noJSON 실패 발생 -> 4,500자로 다이어트하여 5~10초 내 생성 유도.
    static func achievementPromptCharacterBudget(
        for provider: AchievementSuggestionProviderKind
    ) -> Int {
        switch provider {
        case .appleFoundation: return 4_000
        case .mlx: return 6_000
        case .ollama: return 4_500
        }
    }

    /// 목표 추천 생성의 벽시계 상한(초).
    ///
    /// **제품과 평가는 요구가 반대라 값이 하나일 수 없다.** 제품은 사용자를 기다리게 하는
    /// 자리라 상한이 짧아야 하고, 골든셋은 품질을 재는 자리라 속도 제약이 결과를 오염시키면
    /// 안 된다 — 상한에 걸린 케이스는 «모델이 틀렸다» 가 아니라 «머신이 느렸다» 인데
    /// 점수에는 똑같이 0으로 남는다.
    ///
    /// 기본값은 제품 값이고 **`GoalSuggestionEvalTests` 만 이 값을 올려 잡는다.**
    /// `TraceRecorder.shared` 와 같은 방식이다 — 호출 사슬 네 겹에 인자를 뚫는 대신
    /// 평가가 시작할 때 한 번 쓰고 끝나면 되돌린다.
    nonisolated(unsafe) static var achievementSuggestionTimeout: TimeInterval = 180

    /// 골든셋이 쓰는 상한.
    ///
    /// 실측(2026-08-25) 27B 모델이 GPU 에 다 안 올라가 `18% CPU` 로 새면 0.68 tok/s 까지
    /// 떨어져 한 건에 **322초**가 걸렸다. 관측 최댓값 바로 위에 둔 값이라 여유가 크지 않다 —
    /// 근본 해결은 모델을 GPU 에 온전히 올리는 것이다(`iogpu.wired_limit_mb`).
    static let achievementSuggestionEvalTimeout: TimeInterval = 350

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
        static let appearanceDensity = "appearance.density"
        static let popoverTheme = "appearance.popoverTheme"
        static let warmLanternAccent = "appearance.accent.warmLantern"
        static let wineLanternAccent = "appearance.accent.wineLantern"
        static let gamePixelAccent = "appearance.accent.gamePixel"
        static let appIcon = "appearance.appIcon"
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
        static let achievementMinTodosForWeeklySuggestions = "achievement.minTodosForWeeklySuggestions"
        static let achievementMaxWeeklyGoalsPerMonthlyGoal = "achievement.maxWeeklyGoalsPerMonthlyGoal"
        static let achievementSuggestionExcludedMemoIcons = "achievement.suggestionExcludedMemoIcons"
        static let achievementSuggestionProvider = "achievement.suggestionProvider"
        /// 주간·월간을 동시에 돌릴지 하나씩 돌릴지 **강제**하는 숨김 값. 기본은 공급자가 정한다.
        /// `defaults write com.horonghorong.app achievement.executionStrategy -string sequential`
        static let achievementExecutionStrategy = "achievement.executionStrategy"
        static let achievementSuggestionMLXModel = "achievement.suggestionMLXModel"
        static let achievementSuggestionOllamaModel = "achievement.suggestionOllamaModel"
        static let achievementDismissedSuggestionKeys = "achievement.dismissedSuggestionKeys"
        static let rewardWeeklyGoalPoints = "reward.weeklyGoalPoints"
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
        static let companionFocusNudgeEnabled = "companion.focusNudgeEnabled"
        /// 사용자가 등록한 넛지 문구. 한 줄에 하나씩.
        static let companionFocusNudgeMessages = "companion.focusNudgeMessages"
        /// 직전에 쓴 문구. 같은 말이 연달아 나오지 않게 한다.
        static let companionFocusNudgeLastMessage = "companion.focusNudgeLastMessage"
        static let companionFocusNudgeDetectionMode = "companion.focusNudgeDetectionMode"
        static let companionFocusNudgeRequiredFeedbackCount =
            "companion.focusNudgeRequiredFeedbackCount"
        static let companionFocusNudgeManualFocusPercent =
            "companion.focusNudgeManualFocusPercent"
        static let companionFocusNudgeManualMaxAppSwitches =
            "companion.focusNudgeManualMaxAppSwitches"
        static let companionFocusNudgeFrequencyMode = "companion.focusNudgeFrequencyMode"
        static let companionFocusNudgeMaximumPerSession =
            "companion.focusNudgeMaximumPerSession"
        static let companionFocusNudgePendingEvents = "companion.focusNudgePendingEvents"
        static let companionFocusNudgeSessionState = "companion.focusNudgeSessionState"
        static let companionUserNickname = "companion.userNickname"
        static let companionUserNote = "companion.userNote"
        static let companionOnboardingSeen = "companion.onboardingSeen"
        static let companionChatProvider = "companion.chatProvider"
        static let companionOllamaModel = "companion.ollamaModel"
        static let companionMLXModel = "companion.mlxModel"
        /// 한 번이라도 끝까지 준비된 MLX 모델들. 대화 중 자동 로드를 허용할지 판단하는 데 쓴다.
        /// 실제로 읽고 쓰는 쪽은 `HorongAIMLX` 의 `MLXModelStore.preparedModelsDefaultsKey` 다. 값이 같아야 한다.
        static let companionMLXPreparedModels = "companion.mlxPreparedModels"
        static let companionBubbleSize = "companion.bubbleSize"
        /// AI 실험실에서 사람이 남긴 평가(👍/👎/메모). "케이스ID|레벨" → 평가 의 JSON.
        static let aiLabRatings = "ailab.ratings"
        /// 골든셋 채점 결과가 있는 `Evals/` 폴더 경로.
        ///
        /// 결과(`Evals/results/`)는 gitignore 된 실행 산출물이라 앱에 번들할 수 없다.
        /// 사용자가 한 번 지정하면 기억한다. 앱 샌드박스가 꺼져 있어 경로만으로 충분하다.
        static let aiLabEvalsDirectory = "ailab.evalsDirectory"
        /// 개발자 전용 탭(AI 실험실) 노출 여부. Release 빌드에서 직접 켤 때만 쓰는 숨김 플래그.
        /// `defaults write com.horonghorong.app ailab.enabled -bool YES` 후 앱 재시작.
        static let aiLabEnabled = "ailab.enabled"
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
    static let defaultAchievementMinTodosForWeeklySuggestions = 2
    static let defaultAchievementMaxWeeklyGoalsPerMonthlyGoal = 4
    static let legacyAchievementSuggestionExcludedMemoIconsRaw = "☕️,💡,📜"
    static let defaultAchievementSuggestionExcludedMemoIcons = ["☕️", "🌱", "📜"]
    static let defaultAchievementSuggestionExcludedMemoIconsRaw = defaultAchievementSuggestionExcludedMemoIcons.joined(separator: ",")
    static let achievementSuggestionCountRange = 1...8
    static let achievementSuggestionMaxTodoCountRange = 2...12
    static let achievementMonthlySuggestionMinWeeklyGoalCountRange = 2...8
    static let achievementMonthlySuggestionCountRange = 1...6
    static let achievementMinTodosForWeeklySuggestionsRange = 2...12
    static let achievementMaxWeeklyGoalsPerMonthlyGoalRange = 2...8
    static let defaultAchievementJourneyMaxFlagCount = 5
    static let achievementJourneyMaxFlagCountRange = 1...8

    // MARK: - 보상 포인트
    static let defaultRewardWeeklyGoalPoints = 10
    static let rewardWeeklyGoalPointsRange = 1...100
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
    static let defaultNewsOllamaEndpoint = "http://127.0.0.1:11434"
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
                "qwen3.5:35b-a3b": .primary,
                "qwen3.6:35b-a3b-q4_K_M": .primary,
                "qwen3.6:35b-mlx": .primary,
                "qwen3.6:27b-mlx": .quality,
                "qwen3.6:27b-q4_K_M": .quality,
                "qwen3.8:27b": .quality,
                "qwen3.8:27b-mlx": .quality,
                "qwen3.5:9b": .lightweight,
            ]
        case 48..<64:
            return [
                "qwen3:30b": .primary,
                "qwen3:14b": .lightweight,
                "qwen3:32b": .quality,
                "gpt-oss:120b": .caution,
                "qwen3.5:35b-a3b": .quality,
                "qwen3.6:35b-a3b-q4_K_M": .quality,
                "qwen3.6:35b-mlx": .quality,
                "qwen3.6:27b-mlx": .primary,
                "qwen3.6:27b-q4_K_M": .primary,
                "qwen3.8:27b": .primary,
                "qwen3.8:27b-mlx": .primary,
                "qwen3.5:9b": .lightweight,
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
                "qwen3.5:35b-a3b": .unsupported,
                "qwen3.6:35b-a3b-q4_K_M": .unsupported,
                "qwen3.6:35b-mlx": .unsupported,
                "qwen3.6:27b-mlx": .caution,
                "qwen3.6:27b-q4_K_M": .caution,
                "qwen3.8:27b": .caution,
                "qwen3.8:27b-mlx": .caution,
                "qwen3.5:9b": .primary,
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
                "qwen3.5:35b-a3b": .unsupported,
                "qwen3.6:35b-a3b-q4_K_M": .unsupported,
                "qwen3.6:35b-mlx": .unsupported,
                "qwen3.6:27b-mlx": .unsupported,
                "qwen3.6:27b-q4_K_M": .unsupported,
                "qwen3.8:27b": .unsupported,
                "qwen3.8:27b-mlx": .unsupported,
                "qwen3.5:9b": .quality,
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
                "qwen3.5:35b-a3b": .unsupported,
                "qwen3.6:35b-a3b-q4_K_M": .unsupported,
                "qwen3.6:35b-mlx": .unsupported,
                "qwen3.6:27b-mlx": .unsupported,
                "qwen3.6:27b-q4_K_M": .unsupported,
                "qwen3.8:27b": .unsupported,
                "qwen3.8:27b-mlx": .unsupported,
                "qwen3.5:9b": .caution,
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
                "qwen3.5:35b-a3b": .unsupported,
                "qwen3.6:35b-a3b-q4_K_M": .unsupported,
                "qwen3.6:35b-mlx": .unsupported,
                "qwen3.6:27b-mlx": .unsupported,
                "qwen3.6:27b-q4_K_M": .unsupported,
                "qwen3.8:27b": .unsupported,
                "qwen3.8:27b-mlx": .unsupported,
                "qwen3.5:9b": .unsupported,
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
            name: "qwen3.5:9b",
            label: "Qwen3.5 9B",
            detail: "장점: Qwen 3.5 9B. 속도와 성능의 균형이 좋은 모델. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3.5:35b-a3b",
            label: "Qwen3.5 35B-A3B",
            detail: "장점: Qwen 3.5 35B. 고품질 텍스트 생성 모델. 권장 RAM: 48GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3.6:27b-mlx",
            label: "Qwen3.6 27B MLX",
            detail: "장점: Qwen 3.6 27B. MLX 환경에 최적화된 모델. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3.6:27b-q4_K_M",
            label: "Qwen3.6 27B Q4_K_M",
            detail: "장점: Qwen 3.6 27B. 양자화 모델로 적은 메모리로 구동 가능. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3.8:27b",
            label: "Qwen3.8 27B",
            detail: "장점: 최신 Qwen3.8 27B로 긴 지시와 구조화 출력 품질을 비교하기 좋습니다. 대형 모델이라 목표 추천 품질 검증용으로 권장. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: true
        ),
        NewsOllamaModelOption(
            name: "qwen3.8:27b-mlx",
            label: "Qwen3.8 27B MLX",
            detail: "장점: Apple Silicon에서 Ollama의 MLX 엔진을 사용해 응답 속도와 메모리 효율을 높인 Qwen3.8 27B입니다. M칩 Mac의 목표 추천 품질 검증용으로 권장. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: true
        ),
        NewsOllamaModelOption(
            name: "qwen3.6:35b-a3b-q4_K_M",
            label: "Qwen3.6 35B-A3B Q4_K_M",
            detail: "장점: Qwen 3.6 35B. 대형 양자화 모델로 높은 품질과 효율성 제공. 권장 RAM: 48GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "qwen3.6:35b-mlx",
            label: "Qwen3.6 35B MLX",
            detail: "장점: Qwen 3.6 35B. MLX 환경에 최적화된 대형 모델. 권장 RAM: 48GB+.",
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
        NewsOllamaModelOption(
            name: "exaone3:7.8b",
            label: "EXAONE 3.0 7.8B",
            detail: "장점: 한국어와 영어에 매우 특화되어 있으며 어휘력이 유창함. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "exaone-deep:7.8b",
            label: "EXAONE Deep 7.8B",
            detail: "장점: 한국어 중심의 깊은 추론과 문제 해결에 강한 모델. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "llama3.1:8b",
            label: "Llama 3.1 8B",
            detail: "장점: 구조화 출력과 복잡한 지시 이행에 매우 탁월한 Meta의 최신 모델. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "mistral-nemo:12b",
            label: "Mistral Nemo 12B",
            detail: "장점: 긴 컨텍스트와 다국어 처리에 능숙하며 밸런스가 좋은 모델. 권장 RAM: 24GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "phi3.5:3.8b",
            label: "Phi-3.5 Mini",
            detail: "장점: 매우 작고 가벼우면서도 뛰어난 추론 능력을 가진 소형 모델. 권장 RAM: 8GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "solar:10.7b",
            label: "Solar 10.7B",
            detail: "장점: Upstage에서 만든 한국어/영어 최적화 모델. 맥락 이해와 논리력이 매우 뛰어남. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "eeve:10.8b",
            label: "EEVE-Korean 10.8B",
            detail: "장점: 한국인처럼 가장 자연스럽고 유창한 대화가 가능. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "command-r:35b",
            label: "Command R 35B",
            detail: "장점: RAG와 도구 사용, JSON 포맷 출력에 미친 성능을 보여주는 엔터프라이즈급 모델. 권장 RAM: 32GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "aya:8b",
            label: "Aya 23 8B",
            detail: "장점: 23개 다국어 특화 모델로 한국어 성능도 훌륭함. 권장 RAM: 16GB+.",
            availability: .local,
            isRecommended: false
        ),
        NewsOllamaModelOption(
            name: "deepseek-v2:16b",
            label: "DeepSeek V2 Lite 16B",
            detail: "장점: 코딩 및 수학적 추론에 강한 MoE 경량 모델. 권장 RAM: 24GB+.",
            availability: .local,
            isRecommended: false
        ),
    ]
    static var availableNewsOllamaModels: [String] {
        availableNewsOllamaModelOptions.map(\.name)
    }
    // 기본 뉴스 키워드 = 빈 문자열. 사용자가 관심사를 직접 등록하기 전까지 자동 키워드는 넣지 않는다.
    static let defaultNewsInterestKeywords = ""
    static let availableNewsProviders = ["ollama", "codex", "claude", "antigravity", "opencode", "hermes"]
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
        static let scheduleDailyHour = "news.schedule.dailyHour"
        static let scheduleDailyMinute = "news.schedule.dailyMinute"
        static let scheduleIntervalHours = "news.schedule.intervalHours"
        /// 간격 격자의 기준점. `특정 시각` 모드의 시각과는 별개 값이다.
        static let scheduleIntervalStartHour = "news.schedule.intervalStartHour"
        static let scheduleIntervalStartMinute = "news.schedule.intervalStartMinute"
        /// 다음 예정 슬롯. 격자를 유지하는 장부 — 실행 여부와 무관하게 전진한다.
        static let scheduleNextSlotAt = "news.schedule.nextSlotAt"
        /// 마지막으로 수집을 *시작* 한 시각. 수동·자동 모두 기록하며 격자에는 영향을 주지 않고,
        /// 슬롯 직전에 이미 수집했는지 판정하는 데만 쓴다.
        static let scheduleLastRunAt = "news.schedule.lastRunAt"
        /// 지금의 스케줄 설정이 확정된 시각. 이보다 오래된 `lastRunAt` 은 지금 스케줄과 무관하므로
        /// 유예 창 판정에서 제외한다 — 새 스케줄의 첫 회차가 옛 기록 때문에 사라지지 않게 한다.
        static let scheduleConfiguredAt = "news.schedule.configuredAt"
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

    enum AppIconStyle: String, CaseIterable, Identifiable {
        case horong = "app-icon"
        case cozyHorong = "app-icon2"
        case cozyBear = "app-icon3"

        var id: String { rawValue }
        var resourceName: String { rawValue }

        var label: String {
            switch self {
            case .horong: return "호롱"
            case .cozyHorong: return "포근한 호롱"
            case .cozyBear: return "포근한 곰"
            }
        }

        static func normalized(rawValue: String) -> Self {
            Self(rawValue: rawValue) ?? .horong
        }
    }

    static let defaultAppearanceMode = "light"
    static let defaultAppearanceDensity = AppearanceDensity.comfortable.rawValue
    static let defaultPopoverTheme = PopoverTheme.warmLantern.rawValue
    static let defaultAppIcon = AppIconStyle.horong.rawValue

    enum NewsScheduleMode: String, CaseIterable, Identifiable {
        /// 사용자가 팝오버의 `리포트 생성` 을 직접 누를 때만 수집한다.
        case manual
        /// 매일 정해진 시각에 한 번.
        case dailyAt
        /// 고정 격자 위에서 n 시간마다.
        case interval

        var id: String { rawValue }

        var label: String {
            switch self {
            case .manual: return "수동"
            case .dailyAt: return "특정 시각"
            case .interval: return "n시간 간격"
            }
        }

        /// 예전 값(`hourly` / `daily`) 도 흡수한다. 저장된 rawValue 자체를 바꾸는 마이그레이션은
        /// `NewsScheduler.migrateLegacyScheduleIfNeeded()` 가 따로 수행한다.
        static func normalized(rawValue: String) -> Self {
            if let mode = Self(rawValue: rawValue) { return mode }
            switch rawValue {
            case "hourly": return .interval
            case "daily": return .dailyAt
            default: return .manual
            }
        }
    }

    static let defaultNewsSchedule = NewsScheduleMode.manual.rawValue
    static let defaultNewsScheduleDailyHour = 9
    static let defaultNewsScheduleDailyMinute = 0
    static let defaultNewsScheduleIntervalHours = 3
    static let defaultNewsScheduleIntervalStartHour = 9
    static let defaultNewsScheduleIntervalStartMinute = 0

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
