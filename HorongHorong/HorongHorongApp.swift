import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) var timerManager: TimerManager!
    private let appTracker = AppTracker()
    private let quickMemoPanel = QuickMemoPanel()

    private(set) var modelContainer: ModelContainer!

    override init() {
        super.init()
        timerManager = TimerManager(appState: appState)

        let schema = Schema([
            Memo.self,
            FocusSession.self,
            AppUsageRecord.self,
            AppUsageSegment.self,
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

        appTracker.setModelContainer(modelContainer)
        appTracker.startTracking()

        NotificationManager.shared.requestAuthorization()

        HotKeyManager.shared.setup { [weak self] in
            guard let self else { return }
            self.quickMemoPanel.toggle(modelContext: context)
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
    @AppStorage(Constants.AppStorageKey.selectedFocusCategory)
    private var selectedFocusCategory: String = ""

    private var labelStyle: Constants.MenubarLabelStyle {
        Constants.MenubarLabelStyle(rawValue: labelStyleRaw) ?? .timeAndIcon
    }

    private var timeStyle: Constants.MenubarTimeStyle {
        Constants.MenubarTimeStyle(rawValue: timeStyleRaw) ?? .mmss
    }

    var body: some View {
        let state = appState.timerState
        let isActive = state == .focusing || state == .paused || state == .breaking
        let icon = stateIcon(for: state)

        if !isActive || labelStyle == .iconOnly {
            // idle / breakAlert 이거나 사용자가 "아이콘만"을 선택한 경우 — 항상 앱 아이콘.
            Label {
                Text("호롱호롱")
            } icon: {
                Image("MenuBarIcon")
                    .renderingMode(.original)
            }
        } else {
            switch labelStyle {
            case .timeAndIcon:
                Text("\(icon) \(appState.formattedRemaining(style: timeStyle))")
            case .timeOnly:
                Text(appState.formattedRemaining(style: timeStyle))
            case .categoryOnly:
                Text("\(icon) \(categoryText(for: state))")
            case .iconOnly:
                EmptyView() // 위에서 이미 처리.
            }
        }
    }

    private func stateIcon(for state: TimerState) -> String {
        switch state {
        case .focusing, .paused: return "🔥"
        case .breaking:          return "☕️"
        default:                 return ""
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
