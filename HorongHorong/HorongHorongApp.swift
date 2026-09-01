import SwiftUI
import SwiftData
import AppKit

private struct ScreenshotCaptureConfiguration {
    static let targetArgumentName = "--screenshot-target"
    static let tabArgumentName = "--screenshot-tab"
    static let dateArgumentName = "--screenshot-date"
    static let environmentName = "HORONGHORONG_SCREENSHOT_TARGET"
    static let legacyEnvironmentName = "HORONGHORONG_SCREENSHOT_TAB"
    static let environmentDateName = "HORONGHORONG_SCREENSHOT_DATE"
    static let popoverThemeEnvironmentName = "HORONGHORONG_SCREENSHOT_POPOVER_THEME"

    let target: ScreenshotCaptureTarget
    let popoverTheme: String?
    let referenceDate: Date?

    var windowTitle: String {
        "HorongHorong Screenshot - \(target.identifier)"
    }

    var contentSize: CGSize {
        switch target {
        case .popover:
            return CGSize(width: Constants.popoverWidth, height: Constants.popoverMaxHeight)
        case .settings:
            return SettingsTheme.windowDefaultSize
        case .statsDetail, .achievementDetail(_):
            return CGSize(width: Constants.statsWindowWidth, height: Constants.statsWindowHeight)
        case .companion:
            return Constants.companionExpandedOverlaySize
        case .newsReportArchive:
            return CGSize(width: 940, height: 660)
        }
    }

    var styleMask: NSWindow.StyleMask {
        switch target {
        case .popover, .companion:
            return [.borderless]
        case .settings, .statsDetail, .achievementDetail(_), .newsReportArchive:
            return [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        }
    }

    var appearance: NSAppearance? {
        guard case .settings = target else { return nil }
        let mode = UserDefaults.standard.string(forKey: Constants.AppStorageKey.appearanceMode) ?? Constants.defaultAppearanceMode
        switch mode {
        case "dark":
            return NSAppearance(named: .darkAqua)
        case "light":
            return NSAppearance(named: .aqua)
        default:
            return nil
        }
    }

    var colorScheme: ColorScheme? {
        guard case .settings = target else { return nil }
        let mode = UserDefaults.standard.string(forKey: Constants.AppStorageKey.appearanceMode) ?? Constants.defaultAppearanceMode
        switch mode {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            return nil
        }
    }

    var resolvedWindowBackgroundColor: NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(calibratedWhite: 0.11, alpha: 1)
        case .light:
            return .windowBackgroundColor
        case .none:
            return .windowBackgroundColor
        @unknown default:
            return .windowBackgroundColor
        }
    }

    static var current: ScreenshotCaptureConfiguration? {
        let arguments = CommandLine.arguments
        let environment = ProcessInfo.processInfo.environment
        let referenceDate = parsedDate(from: arguments, environment: environment)

        if let argumentIndex = arguments.firstIndex(of: targetArgumentName),
           arguments.indices.contains(argumentIndex + 1),
           let target = ScreenshotCaptureTarget(identifier: arguments[argumentIndex + 1]) {
            return ScreenshotCaptureConfiguration(
                target: target,
                popoverTheme: validatedPopoverTheme,
                referenceDate: referenceDate
            )
        }

        if let argumentIndex = arguments.firstIndex(of: tabArgumentName),
           arguments.indices.contains(argumentIndex + 1),
           let tab = PopoverTab(screenshotIdentifier: arguments[argumentIndex + 1]) {
            return ScreenshotCaptureConfiguration(
                target: .popover(tab),
                popoverTheme: validatedPopoverTheme,
                referenceDate: referenceDate
            )
        }

        if let environmentValue = environment[environmentName],
           let target = ScreenshotCaptureTarget(identifier: environmentValue) {
            return ScreenshotCaptureConfiguration(
                target: target,
                popoverTheme: validatedPopoverTheme,
                referenceDate: referenceDate
            )
        }

        if let environmentValue = environment[legacyEnvironmentName],
           let tab = PopoverTab(screenshotIdentifier: environmentValue) {
            return ScreenshotCaptureConfiguration(
                target: .popover(tab),
                popoverTheme: validatedPopoverTheme,
                referenceDate: referenceDate
            )
        }
        return nil
    }

    private static func parsedDate(from arguments: [String], environment: [String: String]) -> Date? {
        var rawDate: String?
        if let argumentIndex = arguments.firstIndex(of: dateArgumentName),
           arguments.indices.contains(argumentIndex + 1) {
            rawDate = arguments[argumentIndex + 1]
        } else if let envValue = environment[environmentDateName] {
            rawDate = envValue
        }
        guard let rawDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: rawDate)
    }

    private static var validatedPopoverTheme: String? {
        guard let theme = ProcessInfo.processInfo.environment[popoverThemeEnvironmentName],
              Constants.PopoverTheme(rawValue: theme) != nil else {
            return nil
        }
        return theme
    }
}

private enum CompanionScreenshotMode: String {
    case chat
    case schedule

    var screenshotIdentifier: String { rawValue }
}

private enum ScreenshotCaptureTarget {
    case popover(PopoverTab)
    case settings(SettingsTab)
    case statsDetail(StatsViewMode, StatsContentMode = .period, isShorthandFocus: Bool = false)
    case achievementDetail(AchievementDetailScreenshotMode = .progress)
    /// 화면 위에 뜨는 컴패니언.
    case companion(CompanionScreenshotMode = .chat)
    case newsReportArchive

    var identifier: String {
        switch self {
        case .popover(let tab):
            return "popover-\(tab.screenshotIdentifier)"
        case .settings(let tab):
            return "settings-\(tab.screenshotIdentifier)"
        case .statsDetail(let mode, let contentMode, let isShorthandFocus):
            if contentMode == .focus {
                return isShorthandFocus ? "stats-detail-focus" : "stats-detail-focus-\(mode.screenshotIdentifier)"
            }
            return "stats-detail-\(mode.screenshotIdentifier)"
        case .achievementDetail(let mode):
            return mode == .progress ? "achievement-detail" : "achievement-detail-\(mode.screenshotIdentifier)"
        case .companion(let mode):
            return mode == .chat ? "companion" : "companion-\(mode.screenshotIdentifier)"
        case .newsReportArchive:
            return "news-report-archive"
        }
    }

    init?(identifier: String) {
        let parts = identifier.lowercased().split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            if identifier == "achievement-detail" {
                self = .achievementDetail()
                return
            }
            if identifier == "companion" {
                self = .companion(.chat)
                return
            }
            if identifier == "companion-schedule" {
                self = .companion(.schedule)
                return
            }
            if identifier == "news-report-archive" || identifier == "news-archive" {
                self = .newsReportArchive
                return
            }
            if identifier == "stats-detail-focus" || identifier == "stats-focus" {
                self = .statsDetail(.daily, .focus, isShorthandFocus: true)
                return
            }
            if identifier == "stats-detail-focus-daily" {
                self = .statsDetail(.daily, .focus, isShorthandFocus: false)
                return
            }
            if identifier == "stats-detail-focus-weekly" {
                self = .statsDetail(.weekly, .focus, isShorthandFocus: false)
                return
            }
            if identifier == "stats-detail-focus-monthly" {
                self = .statsDetail(.monthly, .focus, isShorthandFocus: false)
                return
            }
            if let tab = PopoverTab(screenshotIdentifier: identifier) {
                self = .popover(tab)
                return
            }
            return nil
        }

        switch parts[0] {
        case "popover":
            guard let tab = PopoverTab(screenshotIdentifier: parts[1]) else { return nil }
            self = .popover(tab)
        case "settings":
            guard let tab = SettingsTab(screenshotIdentifier: parts[1]) else { return nil }
            self = .settings(tab)
        case "stats-detail":
            if parts[1] == "focus" {
                self = .statsDetail(.daily, .focus, isShorthandFocus: true)
                return
            }
            if parts[1] == "focus-daily" {
                self = .statsDetail(.daily, .focus, isShorthandFocus: false)
                return
            }
            if parts[1] == "focus-weekly" {
                self = .statsDetail(.weekly, .focus, isShorthandFocus: false)
                return
            }
            if parts[1] == "focus-monthly" {
                self = .statsDetail(.monthly, .focus, isShorthandFocus: false)
                return
            }
            guard let mode = StatsViewMode(screenshotIdentifier: parts[1]) else { return nil }
            self = .statsDetail(mode, .period, isShorthandFocus: false)
        case "achievement-detail":
            guard let mode = AchievementDetailScreenshotMode(screenshotIdentifier: parts[1]) else { return nil }
            self = .achievementDetail(mode)
        case "companion":
            if parts[1] == "schedule" {
                self = .companion(.schedule)
            } else if parts[1] == "chat" {
                self = .companion(.chat)
            } else {
                return nil
            }
        case "news":
            if parts[1] == "report-archive" || parts[1] == "archive" {
                self = .newsReportArchive
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}

private enum AchievementDetailScreenshotMode: String {
    case progress
    case timelineAll = "timeline-all"
    case journey
    case records
    case reward

    var screenshotIdentifier: String { rawValue }

    var initialState: AchievementDetailScreenshotState {
        switch self {
        case .progress:
            return AchievementDetailScreenshotState(tabIdentifier: "progress")
        case .timelineAll:
            return AchievementDetailScreenshotState(tabIdentifier: "progress", weekGoalFilterIdentifier: "all")
        case .journey:
            return AchievementDetailScreenshotState(tabIdentifier: "journey")
        case .records:
            return AchievementDetailScreenshotState(tabIdentifier: "records")
        case .reward:
            return AchievementDetailScreenshotState(tabIdentifier: "reward")
        }
    }

    init?(screenshotIdentifier: String) {
        self.init(rawValue: screenshotIdentifier.lowercased())
    }
}

private extension PopoverTab {
    var screenshotIdentifier: String {
        switch self {
        case .timer: return "timer"
        case .memo: return "memo"
        case .achievement: return "achievement"
        case .stats: return "stats"
        case .news: return "news"
        case .agent: return "agent"
        }
    }

    init?(screenshotIdentifier: String) {
        switch screenshotIdentifier.lowercased() {
        case "timer":
            self = .timer
        case "memo":
            self = .memo
        case "achievement":
            self = .achievement
        case "stats":
            self = .stats
        case "news":
            self = .news
        case "agent":
            self = .agent
        default:
            return nil
        }
    }
}

private extension SettingsTab {
    var screenshotIdentifier: String {
        rawValue
    }

    init?(screenshotIdentifier: String) {
        self.init(rawValue: screenshotIdentifier.lowercased())
    }
}

private extension StatsViewMode {
    var screenshotIdentifier: String {
        switch self {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        }
    }

    init?(screenshotIdentifier: String) {
        switch screenshotIdentifier.lowercased() {
        case "daily":
            self = .daily
        case "weekly":
            self = .weekly
        case "monthly":
            self = .monthly
        default:
            return nil
        }
    }
}

@MainActor
enum HorongHorongModelSchema {
    static func make() -> Schema {
        Schema([
            Memo.self,
            DiaryEntry.self,
            AchievementGoalRecord.self,
            FocusSession.self,
            PomodoroReflection.self,
            CategoryBehaviorConditionSet.self,
            PomodoroTaskCompletion.self,
            AppUsageRecord.self,
            AppUsageSegment.self,
            BreakTransitionIntent.self,
            AttentionEvent.self,
            AttentionDaySummary.self,
            FocusNudgeEvent.self,
            StatsAggregateCache.self,
            AppCategoryRule.self,
            NewsJob.self,
            NewsReportIndex.self,
            RewardLedgerEntry.self,
            RewardCatalogItem.self,
        ])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) var timerManager: TimerManager!
    private let appTracker = AppTracker()
    private let quickMemoPanel = QuickMemoPanel()
    private var companionController: CompanionController!
    private var screenshotWindow: NSWindow?
    private var notificationObservers: [NSObjectProtocol] = []

    private(set) var modelContainer: ModelContainer!

    override init() {
        super.init()
        timerManager = TimerManager(appState: appState)
        companionController = CompanionController(appState: appState)

        let schema = HorongHorongModelSchema.make()
        do {
            let storeURL = try SwiftDataStoreLocation.storeURL()
            let config = ModelConfiguration(schema: schema, url: storeURL)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error.localizedDescription)")
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NotificationManager.shared
        AppIconManager.applyStoredSelection()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = modelContainer.mainContext

        migrateLegacyOllamaEndpoint()
        migrateRemovedDocumentCategory(in: context)
        migrateMemoSections(in: context)
        mergeDuplicateDiaryEntries(in: context)
        seedDefaultCategoryRules(in: context)
        seedDefaultRewardCatalogItems(in: context)
        repairOrphanedPomodoroRecords(in: context)

        timerManager.setModelContext(context)

        // AI 실행 원문 기록. 개발자 모드에서만 켜지고, 보존 기한이 지난 것은 여기서 정리된다.
        AIRunLog.installTraceRecorder()

        if let screenshotConfig = ScreenshotCaptureConfiguration.current {
            presentScreenshotWindow(config: screenshotConfig)
            return
        }

        appTracker.setModelContainer(modelContainer)
        appTracker.startTracking()

        observeTodayPlanningReminderSelection()
        observeSystemDateChanges()
        TodayPlanningReminderCoordinator.shared.start(modelContext: context)
        NewsScheduler.shared.start(
            pipelineService: appState.newsPipelineService,
            modelContext: context
        )
        NotificationManager.shared.requestAuthorization()
        #if DIRECT_DISTRIBUTION
        AppUpdateManager.shared.refreshState()
        #endif

        HotKeyManager.shared.setup(
            onQuickMemo: { [weak self] in
                guard let self else { return }
                self.quickMemoPanel.toggle(modelContext: context)
            },
            onMenuBarPopover: {
                MenuBarExtraController.toggle()
            },
            onTimerToggle: { [weak self] in
                self?.toggleTimerFromHotkey()
            }
        )

        companionController.start(modelContainer: modelContainer)
    }

    /// `localhost`는 이 기기에서 IPv6(`::1`)로 먼저 해석되지만 Ollama는 IPv4만 열어 둔
    /// 경우가 있어 연결이 거절된다. 예전 기본값만 한 번 IPv4 루프백 주소로 옮긴다.
    /// 사용자가 다른 서버 주소를 직접 지정한 경우에는 건드리지 않는다.
    private func migrateLegacyOllamaEndpoint() {
        let defaults = UserDefaults.standard
        let key = Constants.NewsStorageKey.ollamaEndpoint
        guard defaults.string(forKey: key) == "http://localhost:11434" else { return }
        defaults.set(Constants.defaultNewsOllamaEndpoint, forKey: key)
    }

    /// 기존 메모를 Second Brain 섹션으로 나눈다. 이미 분류된 기록은 다시 쓰지 않는다.
    private func migrateMemoSections(in context: ModelContext) {
        do {
            let memos = try context.fetch(FetchDescriptor<Memo>())
            var changed = false
            for memo in memos where memo.sectionRaw == nil {
                memo.assignSection(
                    MemoClassifier.classify(
                        content: memo.content,
                        startDate: memo.startDate,
                        deadline: memo.deadline
                    )
                )
                changed = true
            }
            if changed {
                try context.save()
            }
        } catch {
            context.rollback()
        }
    }

    /// 같은 날짜 일기가 둘 이상이면 하나만 남긴다.
    ///
    /// `DiaryEntry.day` 에 유일 제약을 걸 수 없어서(`#Unique` 는 macOS 15+) 코드로 지킨다.
    /// 새로 생기는 것은 `DiaryBrowserView.upsert` 가 막고, 이미 생긴 것을 여기서 정리한다.
    /// iCloud 병합·백업 복원처럼 앱 밖에서 들어오는 경로가 있으므로 실행마다 확인한다.
    ///
    /// 남길 것은 **본문이 가장 긴 것**이다. 사용자가 실제로 쓴 글을 잃지 않는 것이
    /// 어느 쪽이 «원본»인지 따지는 것보다 중요하다. 길이가 같으면 최근에 고친 쪽을 남긴다.
    private func mergeDuplicateDiaryEntries(in context: ModelContext) {
        do {
            let entries = try context.fetch(FetchDescriptor<DiaryEntry>())
            let byDay = Dictionary(grouping: entries, by: \.day)
            var didRemove = false

            for (_, group) in byDay where group.count > 1 {
                let keep = group.max {
                    if $0.body.count != $1.body.count { return $0.body.count < $1.body.count }
                    return $0.updatedAt < $1.updatedAt
                }
                for entry in group where entry !== keep {
                    context.delete(entry)
                    didRemove = true
                }
            }

            if didRemove {
                try context.save()
            }
        } catch {
            context.rollback()
        }
    }

    private func toggleTimerFromHotkey() {
        let storedCategory = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.selectedFocusCategory
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = storedCategory.flatMap { $0.isEmpty ? nil : $0 }
            ?? Constants.defaultFocusCategory
        timerManager.toggleFocus(category: category)
    }

    func applicationWillTerminate(_ notification: Notification) {
        TodayPlanningReminderCoordinator.shared.stop()
        companionController.stop()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    /// 알림 배너를 눌렀을 때 오늘 할 일 작성창을 띄운다.
    ///
    /// `queue: .main` 이 필요한 이유는 `observeSystemDateChanges()` 와 같다.
    /// 발송 지점이 백그라운드로 바뀌어도 이 클래스(`@MainActor`)가 안전하게 받는다.
    private func observeTodayPlanningReminderSelection() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .todayPlanningReminderSelected, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.openTodayTaskComposer() }
            }
        )
    }

    private func openTodayTaskComposer() {
        guard UserDefaults.standard.bool(
            forKey: Constants.AppStorageKey.todayPlanningReminderEnabled
        ) else {
            NotificationManager.shared.cancel(
                identifier: Constants.todayPlanningReminderNotificationIdentifier
            )
            return
        }

        let context = modelContainer.mainContext
        guard let memos = try? context.fetch(FetchDescriptor<Memo>()) else { return }
        guard !TodayPlanningReminderPolicy.hasTodayTask(in: memos, now: Date()) else {
            NotificationManager.shared.cancel(
                identifier: Constants.todayPlanningReminderNotificationIdentifier
            )
            return
        }
        quickMemoPanel.showTodayTask(modelContext: context)
    }

    /// 날짜·시계·시간대가 바뀌면 오늘 할 일 알림 예약을 다시 잡는다.
    ///
    /// `queue: .main` 이 반드시 필요하다. `NSCalendarDayChanged` 는 자정에 백그라운드 스레드에서
    /// 발송되는데, 셀렉터 방식 옵저버는 큐를 갈아타지 않고 그 스레드에서 그대로 실행한다.
    /// 이 클래스가 `@MainActor` 라 격리 위반으로 런타임이 앱을 중단시킨다.
    private func observeSystemDateChanges() {
        let handler: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated {
                TodayPlanningReminderCoordinator.shared.systemDateDidChange()
            }
        }
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main, using: handler
                )
            )
        }
    }

    private func presentScreenshotWindow(config: ScreenshotCaptureConfiguration) {
        if let popoverTheme = config.popoverTheme {
            var argumentDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            argumentDomain[Constants.AppStorageKey.popoverTheme] = popoverTheme
            UserDefaults.standard.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain)
        }

        let contentSize = config.contentSize
        let rootView = screenshotRootView(
            for: config.target,
            colorScheme: config.colorScheme,
            referenceDate: config.referenceDate
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: contentSize)
        hostingView.appearance = config.appearance

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: config.styleMask,
            backing: .buffered,
            defer: false
        )
        window.appearance = config.appearance
        window.title = config.windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(config.windowTitle)
        window.contentView = hostingView
        switch config.target {
        case .popover, .companion:
            window.isOpaque = false
            window.backgroundColor = .clear
        case .settings, .statsDetail, .achievementDetail(_), .newsReportArchive:
            window.isOpaque = true
            window.backgroundColor = config.resolvedWindowBackgroundColor
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = config.resolvedWindowBackgroundColor.cgColor
        }
        window.hasShadow = false
        window.level = .floating
        window.sharingType = .readOnly
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        screenshotWindow = window
    }

    private func screenshotRootView(
        for target: ScreenshotCaptureTarget,
        colorScheme: ColorScheme?,
        referenceDate: Date?
    ) -> AnyView {
        switch target {
        case .popover(let tab):
            return AnyView(
                MenuBarPopover(
                    timerManager: timerManager,
                    initialTab: tab,
                    referenceDate: referenceDate ?? Date()
                )
                .environment(appState)
                .modelContainer(modelContainer)
            )
        case .settings(let tab):
            let view = SettingsRoot(initialSelection: tab)
                .environment(appState)
                .modelContainer(modelContainer)
                .frame(
                    width: SettingsTheme.windowDefaultSize.width,
                    height: SettingsTheme.windowDefaultSize.height
                )
            if let colorScheme {
                return AnyView(
                    view.preferredColorScheme(colorScheme)
                        .environment(\.colorScheme, colorScheme)
                )
            } else {
                return AnyView(view)
            }
        case .statsDetail(let mode, let contentMode, _):
            return AnyView(
                StatsDetailWindow(
                    initialViewMode: mode,
                    initialContentMode: contentMode,
                    initialSelectedDate: referenceDate
                )
                .environment(appState)
                .modelContainer(modelContainer)
                .frame(
                    width: Constants.statsWindowWidth,
                    height: Constants.statsWindowHeight
                )
            )
        case .achievementDetail(let mode):
            return AnyView(
                AchievementDetailWindow(initialScreenshotState: mode.initialState)
                    .environment(appState)
                    .modelContainer(modelContainer)
                    .frame(
                        width: Constants.statsWindowWidth,
                        height: Constants.statsWindowHeight
                    )
            )
        case .companion(let mode):
            let state = CompanionPresentationState(
                character: CompanionRegistry.character(
                    for: UserDefaults.standard.string(
                        forKey: Constants.AppStorageKey.companionSelectedIdentifier
                    ) ?? Constants.defaultCompanionIdentifier
                )
            )
            switch mode {
            case .chat:
                // 실제 대화는 모델이 답하므로 화면마다 내용이 달라진다.
                // 문서용 스크린샷은 매번 같아야 해서 대화 내용을 고정해 그린다.
                state.isChatting = true
                state.chatMessages = Self.screenshotChatMessages
            case .schedule:
                // 일정 브리핑 스크린샷.
                state.animation = .review
                let mockEntries = Self.screenshotScheduleEntries
                state.bubble = CompanionBubble(
                    headline: CompanionBriefingSummary.headline(for: mockEntries),
                    message: "오늘의 일정을 알려드릴게요!",
                    schedule: mockEntries,
                    isDismissible: true
                )
            }
            return AnyView(
                CompanionView(state: state)
                    .frame(
                        width: Constants.companionExpandedOverlaySize.width,
                        height: Constants.companionExpandedOverlaySize.height
                    )
            )
        case .newsReportArchive:
            return AnyView(
                NewsReportArchiveWindow()
                    .environment(appState)
                    .modelContainer(modelContainer)
                    .frame(width: 940, height: 660)
            )
        }
    }

    /// 컴패니언 스크린샷에 쓸 고정 대화.
    private static let screenshotChatMessages: [CompanionChatMessage] = [
        CompanionChatMessage(role: .user, text: "안녕 호롱아, 좋은 아침!"),
        CompanionChatMessage(role: .companion, text: "좋은 아침이에요! 오늘도 함께 힘차게 몰입해봐요 ✨"),
        CompanionChatMessage(role: .user, text: "오늘 남은 일정 뭐 있지?"),
        CompanionChatMessage(
            role: .companion,
            text: "오늘 예정된 일정이 4개 있어요. 먼저 «오전 몰입 작업»부터 진행해볼까요?"
        ),
        CompanionChatMessage(
            role: .user,
            text: "19:00에 [호롱호롱] 마인드맵 및 타임라인 생성 기능 구현 일정 추가해줘"
        ),
        CompanionChatMessage(
            role: .companion,
            text: "19:00 «[호롱호롱] 마인드맵 및 타임라인 생성 기능 구현» 일정을 등록했어요! 📝",
            isHovered: true
        ),
    ]

    /// 컴패니언 일정 브리핑 스크린샷에 쓸 고정 일정.
    private static var screenshotScheduleEntries: [CompanionScheduleEntry] {
        let calendar = Calendar.current
        let now = Date()
        let time1 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)
        let time2 = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now)
        let time3 = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        let time4 = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now)
        return [
            CompanionScheduleEntry(time: time1, title: "오전 몰입 작업 (성취 추천 모델 문서화)", isCompleted: true),
            CompanionScheduleEntry(time: time2, title: "주간 팀 싱크 미팅 및 진행 상황 공유", isCompleted: false),
            CompanionScheduleEntry(time: time3, title: "타이머 UI 테마 리팩토링 검토", isCompleted: false),
            CompanionScheduleEntry(time: time4, title: "[호롱호롱] 마인드맵 및 타임라인 생성 기능 구현", isCompleted: false),
        ]
    }

    private func seedDefaultCategoryRules(in context: ModelContext) {
        try? DefaultAppCategoryRuleStore.reconcile(in: context)
    }

    private func seedDefaultRewardCatalogItems(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RewardCatalogItem>())) ?? []
        let defaultItems: [(title: String, emoji: String, cost: Int)] = [
            ("하쿠텐 라멘 먹으러 가기", "🍜", 50),
            ("아이폰 케이스 구매", "📱", 30),
            ("겨울에 스키장 가기", "⛷️", 200),
            ("뉴발란스 운동화 구매", "👟", 120),
        ]
        var nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        for defaultItem in defaultItems {
            if !existing.contains(where: { $0.title == defaultItem.title }) {
                let item = RewardCatalogItem(
                    title: defaultItem.title,
                    emoji: defaultItem.emoji,
                    costPoints: defaultItem.cost,
                    sortOrder: nextOrder
                )
                context.insert(item)
                nextOrder += 1
            }
        }
        try? context.save()
    }

    private func repairOrphanedPomodoroRecords(in context: ModelContext) {
        do {
            let affectedMemos = try PomodoroSessionDeletion.repairOrphanedRecords(
                modelContext: context
            )
            try context.save()
            for memo in affectedMemos {
                PomodoroTaskCompletionRecorder.applyPostSaveEffects(
                    to: memo,
                    modelContext: context
                )
            }
        } catch {
            context.rollback()
        }
    }

    private func migrateRemovedDocumentCategory(in context: ModelContext) {
        let migrationKey = "migration.removedDocumentCategory.v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let oldCategory = Constants.categoryName("문서")
        let newCategory = Constants.categoryName("기록")
        do {
            if oldCategory != newCategory {
                try migrateCategory(from: oldCategory, to: newCategory, in: context)
                CategoryStore.shared.delete(name: oldCategory)
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            context.rollback()
        }
    }

    private func migrateCategory(
        from oldCategory: String,
        to newCategory: String,
        in context: ModelContext
    ) throws {
        guard !context.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        do {
            for segment in try context.fetch(segmentDescriptor) {
                segment.category = newCategory
            }

            let recordDescriptor = FetchDescriptor<AppUsageRecord>(
                predicate: #Predicate { $0.category == oldCategory }
            )
            for record in try context.fetch(recordDescriptor) {
                record.category = newCategory
            }

            let focusDescriptor = FetchDescriptor<FocusSession>()
            for session in try context.fetch(focusDescriptor)
                where session.category == oldCategory {
                session.category = newCategory
            }

            let ruleDescriptor = FetchDescriptor<AppCategoryRule>(
                predicate: #Predicate { $0.category == oldCategory }
            )
            for rule in try context.fetch(ruleDescriptor) {
                rule.category = newCategory
                if let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier),
                   defaultRule.category == newCategory {
                    rule.isUserDefined = false
                } else {
                    rule.isUserDefined = true
                }
            }

            try CategoryBehaviorConditionSetStore.prepareCategoryRename(
                from: oldCategory,
                to: newCategory,
                modelContext: context
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        if UserDefaults.standard.string(forKey: Constants.AppStorageKey.selectedFocusCategory) == oldCategory {
            UserDefaults.standard.set(newCategory, forKey: Constants.AppStorageKey.selectedFocusCategory)
        }

        let oldIdleKey = IdleThresholdStore.userDefaultsKey(for: oldCategory)
        let newIdleKey = IdleThresholdStore.userDefaultsKey(for: newCategory)
        let oldIdleValue = UserDefaults.standard.integer(forKey: oldIdleKey)
        if oldIdleValue > 0 {
            UserDefaults.standard.set(oldIdleValue, forKey: newIdleKey)
            UserDefaults.standard.removeObject(forKey: oldIdleKey)
        }

        CategoryPairStore.shared.renameCategory(from: oldCategory, to: newCategory)
        CategoryManager.shared.loadUserRules(from: context)
    }
}

/// 메뉴바 라벨. 사용자가 선택한 라벨/시간 형식에 맞춰 텍스트·아이콘을 합성한다.
private struct MenuBarLabel: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Constants.AppStorageKey.menubarLabelStyle)
    private var labelStyleRaw: String = Constants.defaultMenubarLabelStyle
    @AppStorage(Constants.AppStorageKey.menubarTimeStyle)
    private var timeStyleRaw: String = Constants.defaultMenubarTimeStyle
    @AppStorage(Constants.AppStorageKey.menubarIcon)
    private var menubarIconRaw: String = Constants.defaultMenubarIcon
    @AppStorage(Constants.AppStorageKey.selectedFocusCategory)
    private var selectedFocusCategory: String = ""

    private var labelStyle: Constants.MenubarLabelStyle {
        Constants.MenubarLabelStyle(rawValue: labelStyleRaw) ?? .timeAndIcon
    }

    private var timeStyle: Constants.MenubarTimeStyle {
        Constants.MenubarTimeStyle(rawValue: timeStyleRaw) ?? .mmss
    }

    private var menubarIcon: Constants.MenubarIconStyle {
        Constants.MenubarIconStyle(rawValue: menubarIconRaw) ?? .horong
    }

    var body: some View {
        let state = appState.timerState
        let isActive = state == .focusing || state == .paused || state == .breaking

        Group {
            if !isActive {
                Label {
                    Text("호롱호롱")
                } icon: {
                    Image(menubarIcon.imageName)
                        .renderingMode(.original)
                }
            } else {
                switch labelStyle {
                case .timeAndIcon:
                    HStack(spacing: 3) {
                        stateIconView(for: state)
                        Text(appState.formattedRemaining(style: timeStyle))
                    }
                case .timeOnly:
                    Text(appState.formattedRemaining(style: timeStyle))
                case .categoryOnly:
                    HStack(spacing: 3) {
                        stateIconView(for: state)
                        Text(categoryText(for: state))
                    }
                case .iconOnly:
                    stateIconView(for: state)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOnboardingPerform)
        ) { notification in
            guard notification.object as? String == "settings.open" else { return }
            NSApp.activate()
            openSettings()
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    let id = window.identifier?.rawValue ?? ""
                    if id.contains("com_apple_SwiftUI_Settings")
                        || window.title.localizedCaseInsensitiveContains("설정") {
                        AppActivation.front(window)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stateIconView(for state: TimerState) -> some View {
        switch state {
        case .focusing, .paused:
            Image("FocusOnMenuBar")
                .renderingMode(.original)
        case .breaking:
            Text("☕️")
        default:
            EmptyView()
        }
    }

    private func categoryText(for state: TimerState) -> String {
        if state == .breaking { return "휴식" }
        let trimmed = selectedFocusCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultFocusCategory : trimmed
    }
}

@main
struct HorongHorongApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var onboardingDemoStore = CompanionOnboardingDemoStore.shared
    @AppStorage(Constants.AppStorageKey.appearanceDensity)
    private var appearanceDensityRaw = Constants.defaultAppearanceDensity

    private var guidedModelContainer: ModelContainer {
        onboardingDemoStore.modelContainer ?? appDelegate.modelContainer
    }

    private var appearanceDensity: AppearanceDensity {
        AppearanceDensity.normalized(rawValue: appearanceDensityRaw)
    }

    var body: some Scene {
        // 팝오버 / 통계 / 설정 — 외관 모드(라이트·다크·시스템) 는 *설정 윈도우에만* 적용한다.
        // 팝오버 UI 는 향후 별도 "팝오버 테마" 가 담당.
        MenuBarExtra {
            MenuBarPopover(timerManager: appDelegate.timerManager)
                .environment(appDelegate.appState)
                .environment(\.appearanceDensity, appearanceDensity)
                .modelContainer(guidedModelContainer)
                .id(onboardingDemoStore.isActive)
        } label: {
            MenuBarLabel(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Window(HubWindowPresenter.windowTitle, id: HubWindowPresenter.windowID) {
            MainHubWindow()
                .environment(appDelegate.appState)
                .environment(\.appearanceDensity, appearanceDensity)
                .dynamicTypeSize(appearanceDensity.dynamicTypeSize)
                .controlSize(appearanceDensity.controlSize)
                .modelContainer(guidedModelContainer)
                .id(onboardingDemoStore.isActive)
        }
        .defaultSize(width: Constants.hubWindowWidth, height: Constants.hubWindowHeight)

        Settings {
            SettingsRoot()
                .environment(appDelegate.appState)
                .modelContainer(appDelegate.modelContainer)
                .frame(
                    minWidth: SettingsTheme.windowMinSize.width,
                    idealWidth: SettingsTheme.windowDefaultSize.width,
                    maxWidth: .infinity,
                    minHeight: SettingsTheme.windowMinSize.height,
                    idealHeight: SettingsTheme.windowDefaultSize.height,
                    maxHeight: .infinity
                )
        }
        .windowResizability(.contentMinSize)
    }
}
