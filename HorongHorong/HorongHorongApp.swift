import SwiftUI
import SwiftData
import AppKit

private struct ScreenshotCaptureConfiguration {
    static let targetArgumentName = "--screenshot-target"
    static let tabArgumentName = "--screenshot-tab"
    static let environmentName = "HORONGHORONG_SCREENSHOT_TARGET"
    static let legacyEnvironmentName = "HORONGHORONG_SCREENSHOT_TAB"

    let target: ScreenshotCaptureTarget

    var windowTitle: String {
        "HorongHorong Screenshot - \(target.identifier)"
    }

    var contentSize: CGSize {
        switch target {
        case .popover:
            return CGSize(width: Constants.popoverWidth, height: Constants.popoverMaxHeight)
        case .settings:
            return SettingsTheme.windowDefaultSize
        case .statsDetail:
            return CGSize(width: Constants.statsWindowWidth, height: Constants.statsWindowHeight)
        }
    }

    var styleMask: NSWindow.StyleMask {
        switch target {
        case .popover:
            return [.borderless]
        case .settings, .statsDetail:
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
            return ScreenshotCaptureConfiguration(target: target)
        }

        if let argumentIndex = arguments.firstIndex(of: tabArgumentName),
           arguments.indices.contains(argumentIndex + 1),
           let tab = PopoverTab(screenshotIdentifier: arguments[argumentIndex + 1]) {
            return ScreenshotCaptureConfiguration(target: .popover(tab))
        }

        if let environmentValue = ProcessInfo.processInfo.environment[environmentName],
           let target = ScreenshotCaptureTarget(identifier: environmentValue) {
            return ScreenshotCaptureConfiguration(target: target)
        }

        if let environmentValue = ProcessInfo.processInfo.environment[legacyEnvironmentName],
           let tab = PopoverTab(screenshotIdentifier: environmentValue) {
            return ScreenshotCaptureConfiguration(target: .popover(tab))
        }
        return nil
    }
}

private enum ScreenshotCaptureTarget {
    case popover(PopoverTab)
    case settings(SettingsTab)
    case statsDetail(StatsViewMode)

    var identifier: String {
        switch self {
        case .popover(let tab):
            return "popover-\(tab.screenshotIdentifier)"
        case .settings(let tab):
            return "settings-\(tab.screenshotIdentifier)"
        case .statsDetail(let mode):
            return "stats-detail-\(mode.screenshotIdentifier)"
        }
    }

    init?(identifier: String) {
        let parts = identifier.lowercased().split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
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
        default:
            return nil
        }
    }
}

private extension PopoverTab {
    var screenshotIdentifier: String {
        switch self {
        case .timer: return "timer"
        case .memo: return "memo"
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) var timerManager: TimerManager!
    private let appTracker = AppTracker()
    private let quickMemoPanel = QuickMemoPanel()
    private var screenshotWindow: NSWindow?

    private(set) var modelContainer: ModelContainer!

    override init() {
        super.init()
        timerManager = TimerManager(appState: appState)

        let schema = Schema([
            Memo.self,
            FocusSession.self,
            AppUsageRecord.self,
            AppUsageSegment.self,
            BreakTransitionIntent.self,
            AttentionEvent.self,
            AttentionDaySummary.self,
            StatsAggregateCache.self,
            AppCategoryRule.self,
            NewsJob.self,
            NewsReportIndex.self,
        ])
        do {
            let storeURL = try SwiftDataStoreLocation.storeURL()
            let config = ModelConfiguration(schema: schema, url: storeURL)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error.localizedDescription)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = modelContainer.mainContext

        migrateRemovedDocumentCategory(in: context)
        seedDefaultCategoryRules(in: context)

        timerManager.setModelContext(context)

        if let screenshotConfig = ScreenshotCaptureConfiguration.current {
            presentScreenshotWindow(config: screenshotConfig)
            return
        }

        appTracker.setModelContainer(modelContainer)
        appTracker.startTracking()

        NotificationManager.shared.requestAuthorization()

        HotKeyManager.shared.setup { [weak self] in
            guard let self else { return }
            self.quickMemoPanel.toggle(modelContext: context)
        }
    }

    private func presentScreenshotWindow(config: ScreenshotCaptureConfiguration) {
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
        case .popover:
            window.isOpaque = false
            window.backgroundColor = .clear
        case .settings, .statsDetail:
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
        }
    }

    private func seedDefaultCategoryRules(in context: ModelContext) {
        let descriptor = FetchDescriptor<AppCategoryRule>()
        let existingRules = (try? context.fetch(descriptor)) ?? []
        let existingBundleIds = Set(existingRules.map(\.bundleIdentifier))

        for rule in Constants.defaultCategoryRules {
            guard !existingBundleIds.contains(rule.bundleId) else { continue }
            let categoryRule = AppCategoryRule(
                bundleIdentifier: rule.bundleId,
                appName: rule.appName,
                category: rule.category,
                isUserDefined: false
            )
            context.insert(categoryRule)
        }
        try? context.save()
    }

    private func migrateRemovedDocumentCategory(in context: ModelContext) {
        let migrationKey = "migration.removedDocumentCategory.v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let oldCategory = Constants.categoryName("문서")
        let newCategory = Constants.categoryName("기록")
        if oldCategory != newCategory {
            migrateCategory(from: oldCategory, to: newCategory, in: context)
            CategoryStore.shared.delete(name: oldCategory)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateCategory(from oldCategory: String, to newCategory: String, in context: ModelContext) {
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        for segment in (try? context.fetch(segmentDescriptor)) ?? [] {
            segment.category = newCategory
        }

        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        for record in (try? context.fetch(recordDescriptor)) ?? [] {
            record.category = newCategory
        }

        let focusDescriptor = FetchDescriptor<FocusSession>()
        for session in (try? context.fetch(focusDescriptor)) ?? [] where session.category == oldCategory {
            session.category = newCategory
        }

        let ruleDescriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        for rule in (try? context.fetch(ruleDescriptor)) ?? [] {
            rule.category = newCategory
            if let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier),
               defaultRule.category == newCategory {
                rule.isUserDefined = false
                CategoryManager.shared.removeUserRule(bundleIdentifier: rule.bundleIdentifier)
            } else {
                rule.isUserDefined = true
                CategoryManager.shared.setUserRule(bundleIdentifier: rule.bundleIdentifier, category: newCategory)
            }
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
        try? context.save()
        CategoryManager.shared.loadUserRules(from: context)
    }
}

/// 메뉴바 라벨. 사용자가 선택한 라벨/시간 형식에 맞춰 텍스트·아이콘을 합성한다.
private struct MenuBarLabel: View {
    let appState: AppState
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

    var body: some Scene {
        // 팝오버 / 통계 / 설정 — 외관 모드(라이트·다크·시스템) 는 *설정 윈도우에만* 적용한다.
        // 팝오버 UI 는 향후 별도 "팝오버 테마" 가 담당.
        MenuBarExtra {
            MenuBarPopover(timerManager: appDelegate.timerManager)
                .environment(appDelegate.appState)
                .modelContainer(appDelegate.modelContainer)
        } label: {
            MenuBarLabel(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Window("호롱호롱 통계", id: "stats-detail") {
            StatsDetailWindow()
                .environment(appDelegate.appState)
                .modelContainer(appDelegate.modelContainer)
        }
        .defaultSize(width: Constants.statsWindowWidth, height: Constants.statsWindowHeight)

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
