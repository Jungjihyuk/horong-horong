import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) var timerManager: TimerManager!
    private let appTracker = AppTracker()
    private let hotKeyManager = HotKeyManager()
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
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

        hotKeyManager.setup { [weak self] in
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

@main
struct HorongHorongApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(timerManager: appDelegate.timerManager)
                .environment(appDelegate.appState)
                .modelContainer(appDelegate.modelContainer)
        } label: {
            Label {
                Text(
                    appDelegate.appState.menuBarTitle.isEmpty
                        ? "호롱호롱"
                        : appDelegate.appState.menuBarTitle
                )
            } icon: {
                Image("MenuBarIcon")
                    .renderingMode(.original)
            }
        }
        .menuBarExtraStyle(.window)

        Window("호롱호롱 통계", id: "stats-detail") {
            StatsDetailWindow()
                .environment(appDelegate.appState)
                .modelContainer(appDelegate.modelContainer)
        }
        .defaultSize(width: Constants.statsWindowWidth, height: Constants.statsWindowHeight)
    }
}
