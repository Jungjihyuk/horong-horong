import Foundation
import SwiftUI
import OSLog

private struct StatsLoadCacheKey: Hashable {
    let mode: StatsViewMode
    let startDate: Date
    let endDate: Date
}

@Observable
@MainActor
final class StatsDetailViewModel {
    let repository: StatsDetailRepository
    let todoRepository: TodoRepository
    let reflectionRepository: PomodoroReflectionRepository
    let statsRepository: StatsRecordRepository
    let statsEditorRepository: StatsRecordEditorRepository

    var viewMode: StatsViewMode = .daily
    var contentMode: StatsContentMode = .period
    var selectedDate: Date = Date()
    var hoveredViewMode: StatsViewMode?
    var showEditor: Bool = false

    var snapshot: StatsDetailSnapshot?
    var focusNudge: FocusNudgeSnapshot?
    var historicalFocusTrend: HistoricalFocusTrendSnapshot?

    private(set) var trackerStore = TrackerStateStore.shared
    private var loadCache: [StatsLoadCacheKey: StatsDetailSnapshot] = [:]
    private var loadCacheOrder: [StatsLoadCacheKey] = []
    private static let loadCacheLimit = 6

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.horonghorong",
        category: "StatsDetailViewModel"
    )

    init(
        repository: StatsDetailRepository,
        todoRepository: TodoRepository,
        reflectionRepository: PomodoroReflectionRepository,
        statsRepository: StatsRecordRepository,
        statsEditorRepository: StatsRecordEditorRepository,
        initialViewMode: StatsViewMode = .daily,
        initialContentMode: StatsContentMode = .period,
        initialSelectedDate: Date? = nil
    ) {
        self.repository = repository
        self.todoRepository = todoRepository
        self.reflectionRepository = reflectionRepository
        self.statsRepository = statsRepository
        self.statsEditorRepository = statsEditorRepository
        self.viewMode = initialViewMode
        self.contentMode = initialContentMode
        if let initialSelectedDate {
            self.selectedDate = initialSelectedDate
        }
    }

    var records: [StatsAppUsageRecord] { snapshot?.records ?? [] }
    var dailySegments: [StatsAppUsageSegment] { snapshot?.dailySegments ?? [] }
    var weekSegments: [StatsAppUsageSegment] { snapshot?.weekSegments ?? [] }
    var periodSegments: [StatsAppUsageSegment] { snapshot?.periodSegments ?? [] }
    var pomodoroComparisonSessions: [PomodoroSessionBreakdown] { snapshot?.pomodoroComparisonSessions ?? [] }
    var timerSessions: [StatsFocusSession] { snapshot?.timerSessions ?? [] }
    var pomodoroReflections: [StatsPomodoroReflection] { snapshot?.pomodoroReflections ?? [] }
    var pomodoroTaskCompletions: [StatsPomodoroTaskCompletion] { snapshot?.pomodoroTaskCompletions ?? [] }
    var breakTransitionIntents: [StatsBreakTransitionIntent] { snapshot?.breakTransitionIntents ?? [] }
    var aggregateSnapshot: StatsAggregateSnapshot? { snapshot?.aggregateSnapshot }
    var attentionDaySummaries: [StatsAttentionDaySummary] { snapshot?.attentionDaySummaries ?? [] }

    var showsVacationIllustration: Bool {
        shouldShowVacationIllustration && contentMode == .period
    }

    var shouldShowVacationIllustration: Bool {
        guard viewMode == .daily else { return false }
        guard trackerStore.vacationRange(containing: selectedDate) != nil else { return false }
        return records.isEmpty && dailySegments.isEmpty && timerSessions.isEmpty
    }

    var vacationDaysInMonth: Set<Date> {
        let ranges = trackerStore.vacationRanges
        guard !ranges.isEmpty else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        var result: Set<Date> = []
        var cursor = start
        while cursor < end {
            if ranges.contains(where: { $0.contains(cursor) }) {
                result.insert(cal.startOfDay(for: cursor))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    func loadData() {
        guard let bounds = periodBounds(for: viewMode, date: selectedDate) else { return }
        let startDate = bounds.start
        let endDate = bounds.end
        let key = StatsLoadCacheKey(mode: viewMode, startDate: startDate, endDate: endDate)

        if let cached = loadCache[key] {
            loadCacheOrder.removeAll { $0 == key }
            loadCacheOrder.append(key)
            snapshot = cached
            refreshFocusCards()
            return
        }

        let loaded = repository.loadDetailSnapshot(
            mode: viewMode,
            startDate: startDate,
            endDate: endDate,
            selectedDate: selectedDate
        )

        loadCache[key] = loaded
        loadCacheOrder.removeAll { $0 == key }
        loadCacheOrder.append(key)
        while loadCacheOrder.count > Self.loadCacheLimit {
            let evictedKey = loadCacheOrder.removeFirst()
            loadCache.removeValue(forKey: evictedKey)
        }

        snapshot = loaded
        refreshFocusCards()
    }

    func refreshFocusCards() {
        let cards = repository.refreshFocusCards(mode: viewMode, selectedDate: selectedDate)
        focusNudge = cards.nudge
        historicalFocusTrend = cards.trend
    }

    func invalidateLoadCache() {
        loadCache.removeAll()
        loadCacheOrder.removeAll()
    }

    func invalidateAggregateCaches(containing date: Date) {
        repository.invalidateAggregateCaches(containing: date)
    }

    func invalidateAllAggregateCaches() {
        repository.invalidateAllAggregateCaches()
    }

    func updateSessionMarkerColor(sessionID: UUID, colorKey: String?) throws {
        try repository.updateSessionMarkerColor(sessionID: sessionID, colorKey: colorKey)
        invalidateLoadCache()
        loadData()
    }

    func updateTaskLink(sessionID: UUID, memoID: UUID?) throws {
        try repository.updateTaskLink(sessionID: sessionID, memoID: memoID)
        invalidateLoadCache()
        loadData()
    }

    func updatePomodoroReflection(
        focusSessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?
    ) throws {
        try repository.updatePomodoroReflection(
            focusSessionID: focusSessionID,
            focusExperience: focusExperience,
            progressResult: progressResult,
            incompleteReason: incompleteReason
        )
        invalidateLoadCache()
        loadData()
    }

    func deletePomodoroReflection(focusSessionID: UUID) throws {
        try repository.deletePomodoroReflection(focusSessionID: focusSessionID)
        invalidateLoadCache()
        loadData()
    }

    func periodBounds(for mode: StatsViewMode, date: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        switch mode {
        case .daily:
            let start = calendar.startOfDay(for: date)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .weekly:
            let start = Constants.mondayWeekStart(for: date, calendar: calendar)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
                return nil
            }
            return (start, end)
        case .monthly:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return (start, end)
        }
    }
}
