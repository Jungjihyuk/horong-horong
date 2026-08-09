import SwiftUI
import SwiftData
import AppKit

private struct ScreenshotCaptureConfiguration {
    static let targetArgumentName = "--screenshot-target"
    static let tabArgumentName = "--screenshot-tab"
    static let environmentName = "HORONGHORONG_SCREENSHOT_TARGET"
    static let legacyEnvironmentName = "HORONGHORONG_SCREENSHOT_TAB"
    static let popoverThemeEnvironmentName = "HORONGHORONG_SCREENSHOT_POPOVER_THEME"

    let target: ScreenshotCaptureTarget
    let popoverTheme: String?

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
        if let argumentIndex = arguments.firstIndex(of: targetArgumentName),
           arguments.indices.contains(argumentIndex + 1),
           let target = ScreenshotCaptureTarget(identifier: arguments[argumentIndex + 1]) {
            return ScreenshotCaptureConfiguration(target: target, popoverTheme: validatedPopoverTheme)
        }

        if let argumentIndex = arguments.firstIndex(of: tabArgumentName),
           arguments.indices.contains(argumentIndex + 1),
           let tab = PopoverTab(screenshotIdentifier: arguments[argumentIndex + 1]) {
            return ScreenshotCaptureConfiguration(target: .popover(tab), popoverTheme: validatedPopoverTheme)
        }

        if let environmentValue = ProcessInfo.processInfo.environment[environmentName],
           let target = ScreenshotCaptureTarget(identifier: environmentValue) {
            return ScreenshotCaptureConfiguration(target: target, popoverTheme: validatedPopoverTheme)
        }

        if let environmentValue = ProcessInfo.processInfo.environment[legacyEnvironmentName],
           let tab = PopoverTab(screenshotIdentifier: environmentValue) {
            return ScreenshotCaptureConfiguration(target: .popover(tab), popoverTheme: validatedPopoverTheme)
        }
        return nil
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
    case statsDetail(StatsViewMode)
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
        case .statsDetail(let mode):
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
            guard let mode = StatsViewMode(screenshotIdentifier: parts[1]) else { return nil }
            self = .statsDetail(mode)
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
    private var dateChangeObservers: [NSObjectProtocol] = []

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

        migrateRemovedDocumentCategory(in: context)
        seedDefaultCategoryRules(in: context)
        repairOrphanedPomodoroRecords(in: context)

        timerManager.setModelContext(context)

        if let screenshotConfig = ScreenshotCaptureConfiguration.current {
            presentScreenshotWindow(config: screenshotConfig)
            return
        }

        appTracker.setModelContainer(modelContainer)
        appTracker.startTracking()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openTodayTaskComposer(_:)),
            name: .todayPlanningReminderSelected,
            object: nil
        )
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
        for observer in dateChangeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        dateChangeObservers.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func openTodayTaskComposer(_ notification: Notification) {
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
            dateChangeObservers.append(
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
        let rootView = screenshotRootView(for: config.target, colorScheme: config.colorScheme)
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

    private func screenshotRootView(for target: ScreenshotCaptureTarget, colorScheme: ColorScheme?) -> AnyView {
        switch target {
        case .popover(let tab):
            return AnyView(
                MenuBarPopover(timerManager: timerManager, initialTab: tab)
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
        case .statsDetail(let mode):
            return AnyView(
                StatsDetailWindow(initialViewMode: mode)
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
        CompanionChatMessage(role: .user, text: "오늘 뭐부터 할까?"),
        CompanionChatMessage(
            role: .companion,
            text: "오전엔 집중이 잘 되니까 «성취 추천 모델 문서화»부터 끝내는 게 좋겠어요. "
                + "짧은 메모 정리는 오후로 미뤄도 괜찮아요."
        ),
    ]

    /// 컴패니언 일정 브리핑 스크린샷에 쓸 고정 일정.
    private static var screenshotScheduleEntries: [CompanionScheduleEntry] {
        let calendar = Calendar.current
        let now = Date()
        let time1 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)
        let time2 = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now)
        let time3 = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        return [
            CompanionScheduleEntry(time: time1, title: "오전 몰입 작업 (성취 추천 모델 문서화)", isCompleted: true),
            CompanionScheduleEntry(time: time2, title: "주간 팀 싱크 미팅 및 진행 상황 공유", isCompleted: false),
            CompanionScheduleEntry(time: time3, title: "타이머 UI 테마 리팩토링 검토", isCompleted: false),
        ]
    }

    private func seedDefaultCategoryRules(in context: ModelContext) {
        try? DefaultAppCategoryRuleStore.reconcile(in: context)
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
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    let id = window.identifier?.rawValue ?? ""
                    if id.contains("com_apple_SwiftUI_Settings")
                        || window.title.localizedCaseInsensitiveContains("설정") {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
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

        Window("호롱호롱 통계", id: "stats-detail") {
            StatsDetailWindow()
                .environment(appDelegate.appState)
                .environment(\.appearanceDensity, appearanceDensity)
                .dynamicTypeSize(appearanceDensity.dynamicTypeSize)
                .controlSize(appearanceDensity.controlSize)
                .modelContainer(guidedModelContainer)
                .id(onboardingDemoStore.isActive)
        }
        .defaultSize(width: Constants.statsWindowWidth, height: Constants.statsWindowHeight)

        Window("호롱호롱 성취", id: "achievement-detail") {
            AchievementDetailWindow()
                .environment(appDelegate.appState)
                .environment(\.appearanceDensity, appearanceDensity)
                .dynamicTypeSize(appearanceDensity.dynamicTypeSize)
                .controlSize(appearanceDensity.controlSize)
                .modelContainer(guidedModelContainer)
                .id(onboardingDemoStore.isActive)
        }
        .defaultSize(width: Constants.statsWindowWidth, height: Constants.statsWindowHeight)

        Window("전체 메모 - 호롱호롱", id: "memo-browser") {
            MemoBrowserWindow()
                .environment(appDelegate.appState)
                .environment(\.appearanceDensity, appearanceDensity)
                .dynamicTypeSize(appearanceDensity.dynamicTypeSize)
                .controlSize(appearanceDensity.controlSize)
                .modelContainer(appDelegate.modelContainer)
        }
        .defaultSize(width: Constants.memoBrowserWindowWidth, height: Constants.memoBrowserWindowHeight)

        Window("뉴스 리포트 보관함", id: "news-report-archive") {
            NewsReportArchiveWindow()
                .environment(appDelegate.appState)
                .environment(\.appearanceDensity, appearanceDensity)
                .dynamicTypeSize(appearanceDensity.dynamicTypeSize)
                .controlSize(appearanceDensity.controlSize)
                .modelContainer(appDelegate.modelContainer)
        }
        .defaultSize(width: 940, height: 660)

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
