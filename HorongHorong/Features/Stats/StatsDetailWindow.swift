import SwiftUI
import SwiftData
import OSLog
import Charts

private struct StatsLoadCacheKey: Hashable {
    let mode: StatsViewMode
    let startDate: Date
    let endDate: Date
}

private struct StatsLoadedData {
    let records: [AppUsageRecord]
    let dailySegments: [AppUsageSegment]
    let weekSegments: [AppUsageSegment]
    let periodSegments: [AppUsageSegment]
    let pomodoroComparisonSessions: [PomodoroSessionBreakdown]
    let timerSessions: [FocusSession]
    let pomodoroReflections: [PomodoroReflection]
    let pomodoroTaskCompletions: [PomodoroTaskCompletion]
    let breakTransitionIntents: [BreakTransitionIntent]
    let aggregateSnapshot: StatsAggregateSnapshot?
    let attentionDaySummaries: [AttentionDaySummary]
}

enum PomodoroComparisonSegmentScope {
    static func includedSessionIDs(
        sessions: [FocusSession]
    ) -> Set<UUID> {
        Set(sessions.map(\.id))
    }
}

enum StatsContentMode {
    case period
    case focus
}

struct StatsDetailWindow: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    @State private var viewMode: StatsViewMode = .daily
    @State private var selectedDate: Date = Date()
    @State private var records: [AppUsageRecord] = []
    @State private var dailySegments: [AppUsageSegment] = []
    @State private var weekSegments: [AppUsageSegment] = []
    @State private var periodSegments: [AppUsageSegment] = []
    @State private var pomodoroComparisonSessions: [PomodoroSessionBreakdown] = []
    @State private var timerSessions: [FocusSession] = []
    @State private var pomodoroReflections: [PomodoroReflection] = []
    @State private var pomodoroTaskCompletions: [PomodoroTaskCompletion] = []
    @State private var breakTransitionIntents: [BreakTransitionIntent] = []
    @State private var aggregateSnapshot: StatsAggregateSnapshot?
    @State private var attentionDaySummaries: [AttentionDaySummary] = []
    @State private var showEditor: Bool = false
    @State private var contentMode: StatsContentMode = .period
    @State private var hoveredViewMode: StatsViewMode?
    @State private var trackerStore = TrackerStateStore.shared
    @State private var loadCache: [StatsLoadCacheKey: StatsLoadedData] = [:]
    @State private var loadCacheOrder: [StatsLoadCacheKey] = []

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.horonghorong",
        category: "StatsDetail"
    )
    private static let loadCacheLimit = 6

    init(initialViewMode: StatsViewMode = .daily) {
        _viewMode = State(initialValue: initialViewMode)
    }

    private var showsVacationIllustration: Bool {
        shouldShowVacationIllustration && contentMode == .period
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if contentMode == .period, !shouldShowVacationIllustration {
                vacationBanner
            }
            ZStack {
                ScrollView {
                    Group {
                        if contentMode == .focus {
                            FocusDetailView(
                                sessions: pomodoroComparisonSessions,
                                reflections: pomodoroReflections,
                                viewMode: viewMode,
                                referenceDate: selectedDate
                            )
                        } else {
                            StatsChartView(
                                records: records,
                                viewMode: viewMode,
                                referenceDate: selectedDate,
                                dailySegments: dailySegments,
                                weekSegments: weekSegments,
                                periodSegments: periodSegments,
                                pomodoroComparisonSessions: pomodoroComparisonSessions,
                                timerSessions: timerSessions,
                                pomodoroReflections: pomodoroReflections,
                                pomodoroTaskCompletions: pomodoroTaskCompletions,
                                breakTransitionIntents: breakTransitionIntents,
                                aggregateSnapshot: aggregateSnapshot,
                                attentionDaySummaries: attentionDaySummaries,
                                vacationDays: viewMode == .monthly ? vacationDaysInMonth : []
                            )
                        }
                    }
                    .padding(20)
                }
                .opacity(showsVacationIllustration ? 0 : 1)
                .allowsHitTesting(!showsVacationIllustration)
                .accessibilityHidden(showsVacationIllustration)

                if showsVacationIllustration {
                    // 일러스트 자체가 휴가 컨텍스트를 충분히 전달하므로 상단 배너는 생략.
                    vacationIllustration
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(PopoverChrome.surface)
        .id(popoverTheme)
        .onAppear {
            logViewTrigger("appear")
            loadRecords()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroReflectionDidChange)) { _ in
            invalidateLoadCache()
            loadRecords()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroSessionDidChange)) { _ in
            invalidateLoadCache()
            loadRecords()
        }
        .onChange(of: selectedDate) { _, _ in
            logViewTrigger("dateChange")
            loadRecords()
        }
        .onChange(of: viewMode) { _, newMode in
            logViewTrigger("modeChange:\(newMode.rawValue)")
            loadRecords()
        }
        // 설정에서 휴가가 추가/삭제(=기록 삭제 옵션 포함)되면 캐시된 @State 가 stale 이 되므로 이때만 다시 로드.
        .onChange(of: trackerStore.vacationRanges.count) { _, _ in
            logViewTrigger("vacationChange")
            invalidateAllAggregateCaches()
            invalidateLoadCache()
            loadRecords()
        }
        .sheet(isPresented: $showEditor, onDismiss: {
            logViewTrigger("editorDismiss")
            invalidateAggregateCaches(containing: selectedDate)
            invalidateLoadCache()
            loadRecords()
        }) {
            ManualSegmentEditorView(date: selectedDate)
        }
    }

    // MARK: - 휴가 표시 배너

    @ViewBuilder
    private var vacationBanner: some View {
        switch viewMode {
        case .daily:
            if let range = trackerStore.vacationRange(containing: selectedDate) {
                VStack(spacing: 0) {
                    vacationBannerView(
                        title: range.label.isEmpty ? "🏖️ 휴가" : "🏖️ \(range.label)",
                        subtitle: "이 날은 휴가 기간이라 기록이 남아있지 않습니다."
                    )
                    Divider()
                }
            }
        case .weekly:
            let (start, end) = periodBounds()
            let days = trackerStore.vacationCount(in: start, end: end)
            if days > 0 {
                VStack(spacing: 0) {
                    vacationBannerView(
                        title: "🏖️ 이 기간에 휴가 \(days)일 포함",
                        subtitle: "휴가로 표시된 날에는 기록이 남아있지 않아 차트에 빈 부분이 있을 수 있어요."
                    )
                    Divider()
                }
            }
        case .monthly:
            // 월간 탭은 히트맵 자체에서 🏖️ 셀로 시각 구분되니까 배너 생략.
            EmptyView()
        }
    }

    private func vacationBannerView(title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - 휴가 일러스트 (일간 + 데이터 없음)

    private var shouldShowVacationIllustration: Bool {
        guard viewMode == .daily else { return false }
        guard trackerStore.vacationRange(containing: selectedDate) != nil else { return false }
        return records.isEmpty && dailySegments.isEmpty && timerSessions.isEmpty
    }

    private var vacationIllustration: some View {
        let range = trackerStore.vacationRange(containing: selectedDate)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d."
        return VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text("🌴🍅🌴")
                .font(.system(size: 56))
            Text("오늘은 푹 쉬세요")
                .font(.title.bold())
            if let range {
                Text("\(range.label.isEmpty ? "휴가 기간" : range.label) · \(formatter.string(from: range.start)) ~ \(formatter.string(from: range.end))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// 현재 선택 월에 포함된 휴가 일자 집합 (월간 히트맵용). 휴가가 없으면 빈 Set.
    private var vacationDaysInMonth: Set<Date> {
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

    private func periodBounds() -> (Date, Date) {
        let cal = Calendar.current
        switch viewMode {
        case .daily:
            let s = cal.startOfDay(for: selectedDate)
            return (s, cal.date(byAdding: .day, value: 1, to: s) ?? s)
        case .weekly:
            let weekStart = Constants.mondayWeekStart(for: selectedDate, calendar: cal)
            return (weekStart, cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart)
        case .monthly:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            return (monthStart, cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart)
        }
    }

    private var toolbar: some View {
        HStack {
            Text("호롱호롱 통계")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PopoverChrome.inkSecondary)

            modePicker

            Spacer()

            dateNavigator

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    contentMode = contentMode == .focus ? .period : .focus
                }
            } label: {
                Label(
                    contentMode == .focus ? "통계로" : "몰입",
                    systemImage: contentMode == .focus ? "chevron.left" : "scope"
                )
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .fixedSize()
            .help(contentMode == .focus ? "기간 통계로 돌아갑니다" : "이 기간의 몰입 세션을 자세히 봅니다")

            Button {
                showEditor = true
            } label: {
                Label("편집", systemImage: "pencil")
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .disabled(viewMode != .daily)
            .help(viewMode == .daily ? "이 날짜의 포모도로와 세그먼트를 수동 편집" : "일간 뷰에서만 사용할 수 있습니다")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PopoverChrome.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: 1)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(StatsViewMode.allCases) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: viewMode == mode ? .bold : .medium, design: .rounded))
                        .foregroundStyle(viewMode == mode ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .frame(width: 54)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                .fill(modeChipFill(for: mode))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredViewMode = isHovering ? mode : nil
                }
            }
        }
        .padding(3)
        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous)
                .stroke(PopoverChrome.divider, lineWidth: 1)
        )
    }

    private func modeChipFill(for mode: StatsViewMode) -> Color {
        if viewMode == mode {
            return PopoverChrome.selectionFill
        }
        if hoveredViewMode == mode {
            return PopoverChrome.card
        }
        return .clear
    }

    private var dateNavigator: some View {
        HStack(spacing: 8) {
            Button {
                navigateDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkSecondary)

            Text(dateRangeText)
                .font(.callout)
                .foregroundStyle(PopoverChrome.ink)
                .frame(minWidth: 120)

            Button {
                navigateDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkSecondary)

            Button("오늘") {
                selectedDate = Date()
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        switch viewMode {
        case .daily:
            formatter.dateFormat = "yyyy년 M월 d일"
            return formatter.string(from: selectedDate)
        case .weekly:
            let calendar = Calendar.current
            let weekStart = Constants.mondayWeekStart(for: selectedDate, calendar: calendar)
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                return ""
            }
            formatter.dateFormat = "M/d"
            return "\(formatter.string(from: weekStart)) ~ \(formatter.string(from: weekEnd))"
        case .monthly:
            formatter.dateFormat = "yyyy년 M월"
            return formatter.string(from: selectedDate)
        }
    }

    private func navigateDate(by value: Int) {
        let calendar = Calendar.current
        switch viewMode {
        case .daily:
            if let newDate = calendar.date(byAdding: .day, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        case .weekly:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        case .monthly:
            if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func loadRecords() {
        guard let bounds = periodBounds(for: viewMode, date: selectedDate) else { return }
        let startDate = bounds.start
        let endDate = bounds.end
        let key = StatsLoadCacheKey(mode: viewMode, startDate: startDate, endDate: endDate)
        let loadStartedAt = Date()
        Self.logger.notice("StatsDetail load start mode=\(viewMode.rawValue, privacy: .public) start=\(Int(startDate.timeIntervalSince1970)) end=\(Int(endDate.timeIntervalSince1970))")

        if let cached = loadCache[key] {
            loadCacheOrder.removeAll { $0 == key }
            loadCacheOrder.append(key)
            let applyStartedAt = Date()
            applyLoadedData(cached)
            let applyElapsedMs = elapsedMs(since: applyStartedAt)
            let elapsedMs = elapsedMs(since: loadStartedAt)
            Self.logger.notice("StatsDetail load cache hit mode=\(viewMode.rawValue, privacy: .public) apply=\(applyElapsedMs)ms total=\(elapsedMs)ms")
            return
        }

        let recordsStartedAt = Date()
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= startDate && $0.date < endDate },
            sortBy: [SortDescriptor(\.date)]
        )
        let fetchedRecords = (try? modelContext.fetch(descriptor)) ?? []
        let recordsElapsedMs = elapsedMs(since: recordsStartedAt)
        Self.logger.notice("StatsDetail records fetch mode=\(viewMode.rawValue, privacy: .public) count=\(fetchedRecords.count) elapsed=\(recordsElapsedMs)ms")

        let fetchedSessions = loadTimerSessions(start: startDate, end: endDate)
        let fetchedPomodoroReflections = loadPomodoroReflections(for: fetchedSessions)
        let fetchedPomodoroTaskCompletions = loadPomodoroTaskCompletions(
            for: fetchedSessions,
            mode: viewMode
        )
        let fetchedBreakTransitions = loadBreakTransitionIntents(start: startDate, end: endDate)
        let attentionSummaryStart = attentionSummaryLoadStart(for: viewMode, start: startDate)
        let finalizedAttentionDays = AttentionDaySummaryRecorder.finalizeCompletedDays(
            from: attentionSummaryStart,
            to: endDate,
            modelContext: modelContext
        )
        let aggregate = loadAggregateSnapshot(
            for: viewMode,
            start: startDate,
            end: endDate,
            records: fetchedRecords,
            timerSessions: fetchedSessions
        )
        let loadedSegments = loadSegments(
            for: viewMode,
            start: startDate,
            end: endDate,
            records: fetchedRecords,
            timerSessions: fetchedSessions,
            aggregateSnapshot: aggregate
        )
        let includedPomodoroSessionIDs = PomodoroComparisonSegmentScope.includedSessionIDs(
            sessions: fetchedSessions
        )
        let loadedPomodoroSegments = loadPomodoroSegments(
            for: fetchedSessions,
            includedSessionIDs: includedPomodoroSessionIDs,
            availablePeriodSegments: loadedSegments.period,
            periodSegmentsCoverFullRange: periodSegmentsCoverFullRange(
                mode: viewMode,
                records: fetchedRecords,
                aggregateSnapshot: aggregate
            ),
            periodStart: startDate,
            periodEnd: endDate
        )
        let loadedPomodoroComparisonSessions = PomodoroComparisonPeriodBuilder.build(
            sessions: fetchedSessions,
            segments: loadedPomodoroSegments,
            periodStart: startDate,
            periodEnd: endDate
        )

        let loadedData = StatsLoadedData(
            records: fetchedRecords,
            dailySegments: loadedSegments.daily,
            weekSegments: loadedSegments.week,
            periodSegments: loadedSegments.period,
            pomodoroComparisonSessions: loadedPomodoroComparisonSessions,
            timerSessions: fetchedSessions,
            pomodoroReflections: fetchedPomodoroReflections,
            pomodoroTaskCompletions: fetchedPomodoroTaskCompletions,
            breakTransitionIntents: fetchedBreakTransitions,
            aggregateSnapshot: aggregate,
            attentionDaySummaries: finalizedAttentionDays
        )
        loadCache[key] = loadedData
        loadCacheOrder.removeAll { $0 == key }
        loadCacheOrder.append(key)
        while loadCacheOrder.count > Self.loadCacheLimit {
            let evictedKey = loadCacheOrder.removeFirst()
            loadCache.removeValue(forKey: evictedKey)
        }
        let applyStartedAt = Date()
        applyLoadedData(loadedData)
        let applyElapsedMs = elapsedMs(since: applyStartedAt)

        let elapsedMs = elapsedMs(since: loadStartedAt)
        Self.logger.notice("StatsDetail loaded mode=\(viewMode.rawValue, privacy: .public) records=\(fetchedRecords.count) dailySegments=\(loadedSegments.daily.count) weekSegments=\(loadedSegments.week.count) periodSegments=\(loadedSegments.period.count) sessions=\(fetchedSessions.count) recordsFetch=\(recordsElapsedMs)ms apply=\(applyElapsedMs)ms total=\(elapsedMs)ms")
    }

    private func applyLoadedData(_ data: StatsLoadedData) {
        records = data.records
        dailySegments = data.dailySegments
        weekSegments = data.weekSegments
        periodSegments = data.periodSegments
        pomodoroComparisonSessions = data.pomodoroComparisonSessions
        timerSessions = data.timerSessions
        pomodoroReflections = data.pomodoroReflections
        pomodoroTaskCompletions = data.pomodoroTaskCompletions
        breakTransitionIntents = data.breakTransitionIntents
        aggregateSnapshot = data.aggregateSnapshot
        attentionDaySummaries = data.attentionDaySummaries
        Self.logger.notice("StatsDetail view update apply mode=\(viewMode.rawValue, privacy: .public) records=\(data.records.count) dailySegments=\(data.dailySegments.count) weekSegments=\(data.weekSegments.count) periodSegments=\(data.periodSegments.count) sessions=\(data.timerSessions.count) reflections=\(data.pomodoroReflections.count) taskCompletions=\(data.pomodoroTaskCompletions.count) breakTransitions=\(data.breakTransitionIntents.count) attentionDays=\(data.attentionDaySummaries.count) aggregate=\(data.aggregateSnapshot == nil ? "none" : "ready", privacy: .public)")
    }

    private func attentionSummaryLoadStart(for mode: StatsViewMode, start: Date) -> Date {
        let calendar = Calendar.current
        switch mode {
        case .daily:
            return start
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: start) ?? start
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: start) ?? start
        }
    }

    private func invalidateLoadCache() {
        loadCache.removeAll()
        loadCacheOrder.removeAll()
        Self.logger.notice("StatsDetail load cache invalidated")
    }

    private func invalidateAggregateCaches(containing date: Date) {
        let descriptor = FetchDescriptor<StatsAggregateCache>()
        let caches = (try? modelContext.fetch(descriptor)) ?? []
        let removed = caches.reduce(into: 0) { count, cache in
            guard cache.periodStart <= date && date < cache.periodEnd else { return }
            modelContext.delete(cache)
            count += 1
        }
        if removed > 0 {
            try? modelContext.save()
            Self.logger.notice("StatsDetail aggregate cache invalidated count=\(removed)")
        }
    }

    private func invalidateAllAggregateCaches() {
        let descriptor = FetchDescriptor<StatsAggregateCache>()
        let caches = (try? modelContext.fetch(descriptor)) ?? []
        for cache in caches {
            modelContext.delete(cache)
        }
        if !caches.isEmpty {
            try? modelContext.save()
            Self.logger.notice("StatsDetail aggregate cache invalidated count=\(caches.count)")
        }
    }

    /// 전환 카운트와 포모도로 상세 표시용. 범위 앞쪽으로 약간 버퍼를 둬서 경계에 걸친 세션도 포함.
    private func loadTimerSessions(start: Date, end: Date) -> [FocusSession] {
        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let startedAt = Date()
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            guard let focusEnd = focusEnd(for: $0) else { return false }
            return $0.startedAt < end && focusEnd > start
        }
        let elapsedMs = elapsedMs(since: startedAt)
        Self.logger.notice("StatsDetail sessions fetch count=\(sessions.count) elapsed=\(elapsedMs)ms")
        return sessions
    }

    private func loadPomodoroReflections(
        for sessions: [FocusSession]
    ) -> [PomodoroReflection] {
        guard !sessions.isEmpty else { return [] }
        let sessionIDs = sessions.map(\.id)
        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { sessionIDs.contains($0.focusSessionID) },
            sortBy: [SortDescriptor(\.answeredAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadPomodoroSegments(
        for sessions: [FocusSession],
        includedSessionIDs: Set<UUID>,
        availablePeriodSegments: [AppUsageSegment],
        periodSegmentsCoverFullRange: Bool,
        periodStart: Date,
        periodEnd: Date
    ) -> [AppUsageSegment] {
        let completedRanges = sessions.compactMap { session -> (Date, Date)? in
            guard includedSessionIDs.contains(session.id),
                  session.startedAt >= periodStart,
                  session.startedAt < periodEnd,
                  isCompletedPomodoro(session),
                  let end = focusEnd(for: session) else {
                return nil
            }
            guard end > session.startedAt else { return nil }
            return (session.startedAt, end)
        }
        var segmentsByID = Dictionary(
            uniqueKeysWithValues: availablePeriodSegments.map { ($0.id, $0) }
        )
        let missingRanges = completedRanges.compactMap { rangeStart, rangeEnd in
            guard periodSegmentsCoverFullRange else { return (rangeStart, rangeEnd) }
            guard rangeEnd > periodEnd else { return nil }
            return (max(rangeStart, periodEnd), rangeEnd)
        }
        for (rangeStart, rangeEnd) in mergedPomodoroSegmentRanges(missingRanges) {
            let descriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate {
                    $0.startTime < rangeEnd && $0.endTime > rangeStart
                },
                sortBy: [SortDescriptor(\.startTime)]
            )
            for segment in (try? modelContext.fetch(descriptor)) ?? [] {
                segmentsByID[segment.id] = segment
            }
        }
        return segmentsByID.values.sorted { $0.startTime < $1.startTime }
    }

    private func mergedPomodoroSegmentRanges(
        _ ranges: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        let maximumGap: TimeInterval = 10 * 60
        let sorted = ranges.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [(start: Date, end: Date)] = []

        for range in sorted.dropFirst() {
            if range.start.timeIntervalSince(current.end) <= maximumGap {
                current.end = max(current.end, range.end)
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    private func periodSegmentsCoverFullRange(
        mode: StatsViewMode,
        records: [AppUsageRecord],
        aggregateSnapshot: StatsAggregateSnapshot?
    ) -> Bool {
        switch mode {
        case .daily:
            return true
        case .weekly:
            return aggregateSnapshot == nil
        case .monthly:
            return aggregateSnapshot == nil && records.isEmpty
        }
    }

    private func loadPomodoroTaskCompletions(
        for sessions: [FocusSession],
        mode: StatsViewMode
    ) -> [PomodoroTaskCompletion] {
        guard mode == .daily, !sessions.isEmpty else { return [] }

        return sessions.compactMap { session in
            let sessionID = session.id
            var descriptor = FetchDescriptor<PomodoroTaskCompletion>(
                predicate: #Predicate { $0.focusSessionID == sessionID }
            )
            descriptor.fetchLimit = 1
            return try? modelContext.fetch(descriptor).first
        }
        .sorted { $0.completedAt < $1.completedAt }
    }

    private func loadBreakTransitionIntents(start: Date, end: Date) -> [BreakTransitionIntent] {
        let descriptor = FetchDescriptor<BreakTransitionIntent>(
            predicate: #Predicate { $0.breakEndedAt >= start && $0.breakEndedAt < end },
            sortBy: [SortDescriptor(\.breakEndedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func focusEnd(for session: FocusSession) -> Date? {
        PomodoroComparisonPeriodBuilder.focusEnd(for: session)
    }

    private func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        PomodoroComparisonPeriodBuilder.isCompleted(session)
    }

    /// 일간 뷰에서는 선택한 하루의 세그먼트, 주간 뷰에서는 해당 주 7일 세그먼트를 읽는다.
    private func loadSegments(
        for mode: StatsViewMode,
        start: Date,
        end: Date,
        records: [AppUsageRecord],
        timerSessions: [FocusSession],
        aggregateSnapshot: StatsAggregateSnapshot?
    ) -> (daily: [AppUsageSegment], week: [AppUsageSegment], period: [AppUsageSegment]) {
        let startedAt = Date()
        switch mode {
        case .daily:
            let dayDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let segments = (try? modelContext.fetch(dayDescriptor)) ?? []
            logSegmentFetch(mode: mode, count: segments.count, startedAt: startedAt, source: "segments")
            return (segments, [], segments)

        case .weekly:
            if aggregateSnapshot != nil {
                logSegmentFetch(mode: mode, count: 0, startedAt: startedAt, source: "aggregateCache")
                return ([], [], [])
            }
            let weekDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let segments = (try? modelContext.fetch(weekDescriptor)) ?? []
            logSegmentFetch(mode: mode, count: segments.count, startedAt: startedAt, source: "segments")
            return ([], segments, segments)

        case .monthly:
            if aggregateSnapshot != nil {
                logSegmentFetch(mode: mode, count: 0, startedAt: startedAt, source: "aggregateCache")
                return ([], [], [])
            }
            if !records.isEmpty {
                logSegmentFetch(mode: mode, count: 0, startedAt: startedAt, source: "records")
                return ([], [], [])
            }
            let monthDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let segments = (try? modelContext.fetch(monthDescriptor)) ?? []
            logSegmentFetch(mode: mode, count: segments.count, startedAt: startedAt, source: "segmentsFallback")
            return ([], [], segments)
        }
    }

    private func logSegmentFetch(mode: StatsViewMode, count: Int, startedAt: Date, source: String) {
        let elapsedMs = elapsedMs(since: startedAt)
        Self.logger.notice("StatsDetail segment load mode=\(mode.rawValue, privacy: .public) source=\(source, privacy: .public) count=\(count) elapsed=\(elapsedMs)ms")
    }

    private func loadAggregateSnapshot(
        for mode: StatsViewMode,
        start: Date,
        end: Date,
        records: [AppUsageRecord],
        timerSessions: [FocusSession]
    ) -> StatsAggregateSnapshot? {
        guard let scope = StatsAggregateScope.value(for: mode) else { return nil }

        let fingerprint = StatsAggregateBuilder.fingerprint(records: records, sessions: timerSessions)
        let startedAt = Date()
        let scopedDescriptor = FetchDescriptor<StatsAggregateCache>(
            predicate: #Predicate { $0.scope == scope },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let lookupStartedAt = Date()
        let scopedCaches = (try? modelContext.fetch(scopedDescriptor)) ?? []
        let caches = scopedCaches.filter {
            abs($0.periodStart.timeIntervalSince(start)) < 1 &&
            abs($0.periodEnd.timeIntervalSince(end)) < 1
        }
        Self.logger.notice("StatsDetail aggregate cache lookup mode=\(mode.rawValue, privacy: .public) scoped=\(scopedCaches.count) matched=\(caches.count) elapsed=\(elapsedMs(since: lookupStartedAt))ms")

        if let cache = caches.first(where: { $0.sourceFingerprint == fingerprint }),
           let snapshot = StatsAggregateCacheCodec.decode(cache.payload) {
            let staleCaches = caches.filter { $0.id != cache.id }
            for stale in staleCaches {
                modelContext.delete(stale)
            }
            if !staleCaches.isEmpty {
                try? modelContext.save()
            }
            logAggregateCache(mode: mode, source: "hit", rows: snapshot.dailyCategories.count, startedAt: startedAt)
            return snapshot
        }

        if let previousCache = caches.first,
           let previousSnapshot = StatsAggregateCacheCodec.decode(previousCache.payload) {
            let buildStartedAt = Date()
            let recordSnapshot = StatsAggregateBuilder.build(
                mode: mode,
                start: start,
                end: end,
                records: records,
                segments: [],
                timerSessions: timerSessions
            )
            Self.logger.notice("StatsDetail aggregate build mode=\(mode.rawValue, privacy: .public) source=recordsRefresh rows=\(recordSnapshot.dailyCategories.count) elapsed=\(elapsedMs(since: buildStartedAt))ms")
            let refreshedSnapshot = StatsAggregateSnapshot(
                dailyCategories: recordSnapshot.dailyCategories,
                dailyFocusLevels: previousSnapshot.dailyFocusLevels
            )
            if let payload = StatsAggregateCacheCodec.encode(refreshedSnapshot) {
                previousCache.sourceFingerprint = fingerprint
                previousCache.payload = payload
                previousCache.updatedAt = Date()

                let staleCaches = caches.filter { $0.id != previousCache.id }
                for stale in staleCaches {
                    modelContext.delete(stale)
                }
                try? modelContext.save()
            }
            logAggregateCache(mode: mode, source: "recordsRefresh", rows: refreshedSnapshot.dailyCategories.count, startedAt: startedAt)
            return refreshedSnapshot
        }

        let segmentsStartedAt = Date()
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let segments = (try? modelContext.fetch(segmentDescriptor)) ?? []
        let segmentElapsedMs = elapsedMs(since: segmentsStartedAt)
        Self.logger.notice("StatsDetail aggregate source segments mode=\(mode.rawValue, privacy: .public) count=\(segments.count) elapsed=\(segmentElapsedMs)ms")

        let buildStartedAt = Date()
        let snapshot = StatsAggregateBuilder.build(
            mode: mode,
            start: start,
            end: end,
            records: records,
            segments: segments,
            timerSessions: timerSessions
        )
        Self.logger.notice("StatsDetail aggregate build mode=\(mode.rawValue, privacy: .public) source=segments rows=\(snapshot.dailyCategories.count) elapsed=\(elapsedMs(since: buildStartedAt))ms")

        guard let payload = StatsAggregateCacheCodec.encode(snapshot) else {
            logAggregateCache(mode: mode, source: "encodeFailed", rows: snapshot.dailyCategories.count, startedAt: startedAt)
            return snapshot
        }

        for cache in caches {
            modelContext.delete(cache)
        }
        modelContext.insert(StatsAggregateCache(
            scope: scope,
            periodStart: start,
            periodEnd: end,
            sourceFingerprint: fingerprint,
            payload: payload
        ))
        try? modelContext.save()
        logAggregateCache(mode: mode, source: "rebuilt", rows: snapshot.dailyCategories.count, startedAt: startedAt)
        return snapshot
    }

    private func logAggregateCache(mode: StatsViewMode, source: String, rows: Int, startedAt: Date) {
        let elapsedMs = elapsedMs(since: startedAt)
        Self.logger.notice("StatsDetail aggregate cache mode=\(mode.rawValue, privacy: .public) source=\(source, privacy: .public) rows=\(rows) elapsed=\(elapsedMs)ms")
    }

    private func logViewTrigger(_ event: String) {
        Self.logger.notice("StatsDetail view trigger event=\(event, privacy: .public) mode=\(viewMode.rawValue, privacy: .public) selectedDay=\(Int(Calendar.current.startOfDay(for: selectedDate).timeIntervalSince1970))")
    }

    private func elapsedMs(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1_000)
    }

    private func periodBounds(for mode: StatsViewMode, date: Date) -> (start: Date, end: Date)? {
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

// MARK: - 몰입 상세 (몰입 지도 + 세션별 지표)

/// 몰입 지도 가로축 후보. `입력 활동`은 아직 수집하지 않아 비활성(준비 중).
enum FocusSessionMetric: String, CaseIterable, Identifiable {
    case continuousFocus
    case appSwitches
    case inputActivity
    case appCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuousFocus: return "연속 몰입"
        case .appSwitches: return "앱 전환"
        case .inputActivity: return "입력 활동"
        case .appCount: return "사용 앱 수"
        }
    }

    var axisLabel: String {
        switch self {
        case .continuousFocus: return "연속 몰입 (분) →"
        case .appSwitches: return "앱 전환 (회) →"
        case .inputActivity: return "입력 활동 (%) →"
        case .appCount: return "사용 앱 수 (개) →"
        }
    }

    var isAvailable: Bool { true }

    func value(_ row: FocusSessionRow) -> Double {
        switch self {
        case .continuousFocus: return row.continuousFocusMinutes
        case .appSwitches: return Double(row.observation.appSwitchCount)
        case .inputActivity: return (row.inputActivityRatio ?? 0) * 100
        case .appCount: return Double(row.observation.apps.count)
        }
    }

    /// 이 지표를 지도에 그릴 값이 있는지. 입력 활동은 수집된 세션만 그린다.
    func hasValue(_ row: FocusSessionRow) -> Bool {
        switch self {
        case .inputActivity: return row.inputActivityRatio != nil
        default: return true
        }
    }
}

/// 몰입 지도·세션 리스트가 쓰는 한 세션의 파생 지표. 모두 observation 에서 계산.
/// 몰입 지도 점에 쓸 수 있는 사용자 지정 색 팔레트. 저장은 key 문자열로 한다.
struct FocusMarkerColor: Identifiable {
    let key: String
    let name: String
    let color: Color
    var id: String { key }
}

enum FocusMarkerPalette {
    static let colors: [FocusMarkerColor] = [
        .init(key: "blue", name: "파랑", color: .blue),
        .init(key: "teal", name: "청록", color: .teal),
        .init(key: "green", name: "초록", color: .green),
        .init(key: "yellow", name: "노랑", color: .yellow),
        .init(key: "orange", name: "주황", color: .orange),
        .init(key: "red", name: "빨강", color: .red),
        .init(key: "pink", name: "분홍", color: .pink),
        .init(key: "purple", name: "보라", color: .purple),
        .init(key: "gray", name: "회색", color: .gray),
    ]

    static func color(forKey key: String?) -> Color? {
        guard let key else { return nil }
        return colors.first { $0.key == key }?.color
    }
}

struct FocusSessionRow: Identifiable {
    let id: UUID
    let title: String
    let category: String
    let startedAt: Date
    let durationSeconds: Int
    let rating: Int?
    let observation: PomodoroSessionObservation
    let inputActivityRatio: Double?
    let markerColorKey: String?

    var inputActivityPercent: Int? {
        inputActivityRatio.map { Int(($0 * 100).rounded()) }
    }

    var continuousFocusMinutes: Double {
        Double(observation.longestContinuousAppUsage?.durationSeconds ?? 0) / 60
    }
    var activeRatio: Double {
        observation.sessionSeconds > 0
            ? Double(observation.recordedSeconds) / Double(observation.sessionSeconds)
            : 0
    }
    var minutesPerSwitch: Double? {
        guard observation.appSwitchCount > 0 else { return nil }
        return Double(observation.attributedSeconds) / Double(observation.appSwitchCount) / 60
    }
    var appCount: Int { observation.apps.count }
    var hasComparableRecord: Bool { observation.recordedSeconds > 0 }
    var color: Color {
        FocusMarkerPalette.color(forKey: markerColorKey) ?? Constants.categoryColor(for: category)
    }
    var emoji: String { Constants.categoryEmoji(for: category) }
}

/// 회고(`focusExperience`)를 1–5 몰입 점수로. `unsure`/미작성은 값 없음(지도 제외).
private func focusRating(_ experience: PomodoroFocusExperience?) -> Int? {
    switch experience {
    case .deeplyFocused: return 4
    case .mostlyFocused: return 3
    case .frequentlyDistracted: return 2
    case .difficultToFocus: return 1
    case .unsure, .none: return nil
    }
}

private let focusTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

/// 세로축(몰입 점수)에 마우스를 올리면 보여줄 설명. 점수는 종료 회고와 1:1로 대응한다.
private let focusScoreLegend = """
몰입 점수 = 포모도로가 끝난 뒤 고른 집중 경험
4 · 깊게 몰입했어요
3 · 대체로 집중했어요
2 · 자주 흐트러졌어요
1 · 집중하기 어려웠어요
‘잘 모르겠어요’는 지도에서 빼요
"""

struct FocusDetailView: View {
    let sessions: [PomodoroSessionBreakdown]
    let reflections: [PomodoroReflection]
    let viewMode: StatsViewMode
    let referenceDate: Date

    @Environment(\.modelContext) private var modelContext
    @State private var xMetric: FocusSessionMetric = .continuousFocus
    @State private var selectedSessionID: UUID?
    @State private var showsScoreInfo = false
    @State private var colorPickerSessionID: UUID?

    private var rows: [FocusSessionRow] {
        let reflectionByID = Dictionary(
            reflections.map { ($0.focusSessionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions.compactMap { session -> FocusSessionRow? in
            guard let reflection = reflectionByID[session.id] else { return nil }
            return FocusSessionRow(
                id: session.id,
                title: session.taskTitle ?? "\(session.category) 세션",
                category: session.category,
                startedAt: session.startedAt,
                durationSeconds: session.durationSeconds,
                rating: focusRating(reflection.focusExperience),
                observation: session.observation,
                inputActivityRatio: session.inputActivityRatio,
                markerColorKey: session.markerColorKey
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    private var mapRows: [FocusSessionRow] {
        rows.filter { $0.rating != nil && $0.hasComparableRecord }
    }

    /// 선택한 가로축 지표로 실제 그릴 수 있는 세션(예: 입력 활동은 수집된 세션만).
    private var plottedRows: [FocusSessionRow] {
        mapRows.filter { xMetric.hasValue($0) }
    }

    private var selectedRow: FocusSessionRow? {
        selectedSessionID.flatMap { id in rows.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if rows.isEmpty {
                emptyState
            } else {
                focusMapCard
                sessionListSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.largeTitle)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("이 기간에 회고를 남긴 포모도로가 없어요.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text("포모도로가 끝난 뒤 집중 경험을 선택하면 몰입 지도에서 볼 수 있어요.")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: 몰입 지도

    private var focusMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("몰입 지도")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                scoreInfoButton
                Spacer()
                Text("↑ 위로 갈수록 내가 느낀 몰입이 높아요 · 원이 클수록 오래 집중")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            HStack(spacing: 8) {
                Text("가로 기준")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                ForEach(FocusSessionMetric.allCases) { metric in
                    metricChip(metric)
                }
                Spacer(minLength: 0)
            }

            if mapRows.isEmpty {
                Text("아직 몰입 점수를 매긴 세션이 없어요. (‘잘 모르겠음’ 회고만 있거나 앱 기록이 부족해요)")
                    .font(.callout)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else if plottedRows.isEmpty {
                Text("이 기간에는 ‘입력 활동’을 기록한 세션이 아직 없어요.")
                    .font(.callout)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                focusChart
            }

            if let selected = selectedRow {
                selectedDetailLine(selected)
            } else {
                Text("점을 누르면 그 세션의 상세가 보여요. 원이 클수록 전환 없이 오래 집중한 세션이에요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popoverCard(padding: 16)
    }

    /// 세로축(몰입 점수)이 무슨 뜻인지 알려주는 ⓘ. 마우스를 올리면 툴팁, 누르면 팝오버.
    private var scoreInfoButton: some View {
        Button {
            showsScoreInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .buttonStyle(.plain)
        .help(focusScoreLegend)
        .popover(isPresented: $showsScoreInfo) {
            scoreLegendPopover
        }
        .accessibilityLabel("몰입 점수 설명")
    }

    private var scoreLegendPopover: some View {
        let scores = [4, 3, 2, 1]
        let labels = ["깊게 몰입했어요", "대체로 집중했어요", "자주 흐트러졌어요", "집중하기 어려웠어요"]
        return VStack(alignment: .leading, spacing: 7) {
            Text("몰입 점수 = 세로축")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text("포모도로가 끝난 뒤 고른 집중 경험이에요.")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(scores.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(scores[index])")
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 14, alignment: .trailing)
                        .foregroundStyle(PopoverChrome.accent)
                    Text(labels[index])
                        .font(.callout)
                        .foregroundStyle(PopoverChrome.ink)
                }
            }
            Text("‘잘 모르겠어요’는 몰입 점수가 없어 지도에서 빼요.")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 250)
    }

    private func metricChip(_ metric: FocusSessionMetric) -> some View {
        let selected = xMetric == metric
        return Button {
            if metric.isAvailable { xMetric = metric }
        } label: {
            HStack(spacing: 4) {
                Text(metric.title)
                if !metric.isAvailable {
                    Text("준비 중")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(PopoverChrome.divider, in: Capsule())
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .foregroundStyle(
                !metric.isAvailable
                    ? PopoverChrome.inkTertiary
                    : (selected ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
            )
            .background(
                selected ? PopoverChrome.selectionFill : PopoverChrome.surface,
                in: Capsule()
            )
            .overlay(Capsule().stroke(PopoverChrome.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!metric.isAvailable)
        .help(metric.isAvailable ? "가로축을 이 지표로 바꿉니다" : "입력 활동은 아직 수집하지 않아요 (준비 중)")
    }

    private var focusChart: some View {
        let xMax = max(1, plottedRows.map { xMetric.value($0) }.max() ?? 1)
        let maxMinutes = max(1, plottedRows.map(\.continuousFocusMinutes).max() ?? 1)
        return Chart(plottedRows) { row in
            PointMark(
                x: .value(xMetric.title, xMetric.value(row)),
                y: .value("몰입", Double(row.rating ?? 0))
            )
            .symbolSize(60 + (row.continuousFocusMinutes / maxMinutes) * 340)
            .foregroundStyle(row.color)
            .opacity(selectedSessionID == nil || selectedSessionID == row.id ? 0.9 : 0.28)
        }
        .chartXScale(domain: -(xMax * 0.08)...(xMax * 1.1))
        .chartYScale(domain: 0.5...4.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 2, 3, 4]) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxisLabel(xMetric.axisLabel, alignment: .trailing)
        .frame(height: 300)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { event in
                            selectNearest(to: event.location, proxy: proxy, geo: geo)
                        }
                    )
            }
        }
    }

    private func selectNearest(to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        let point = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        var best: (id: UUID, distance: CGFloat)?
        for row in plottedRows {
            guard let px = proxy.position(forX: xMetric.value(row)),
                  let py = proxy.position(forY: Double(row.rating ?? 0)) else { continue }
            let distance = hypot(px - point.x, py - point.y)
            if best == nil || distance < best!.distance {
                best = (row.id, distance)
            }
        }
        if let best, best.distance < 44 {
            selectedSessionID = (selectedSessionID == best.id) ? nil : best.id
        } else {
            selectedSessionID = nil
        }
    }

    private func selectedDetailLine(_ row: FocusSessionRow) -> some View {
        var parts: [String] = [focusTimeFormatter.string(from: row.startedAt)]
        if let rating = row.rating { parts.append("자기평가 \(rating)/4") }
        parts.append("연속 \(Int(row.continuousFocusMinutes))분")
        if let mps = row.minutesPerSwitch {
            parts.append("전환당 \(String(format: "%.1f", mps))분")
        }
        parts.append("활성 \(Int((row.activeRatio * 100).rounded()))%")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(row.emoji) \(row.title)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Text("· " + parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    // MARK: 세션별 지표

    private var sessionListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("세션별 지표")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("내 평가 + 측정값 그대로")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            ForEach(rows) { row in
                sessionCard(row)
            }
        }
    }

    /// 세션 카드의 색 스와치. 누르면 팔레트 팝오버로 이 세션의 지도 점 색을 바꾼다.
    private func colorSwatchButton(for row: FocusSessionRow) -> some View {
        Button {
            colorPickerSessionID = row.id
        } label: {
            Circle()
                .fill(row.color)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(PopoverChrome.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("이 세션의 몰입 지도 점 색을 바꿉니다")
        .popover(isPresented: Binding(
            get: { colorPickerSessionID == row.id },
            set: { if !$0 { colorPickerSessionID = nil } }
        )) {
            colorSwatchPicker(for: row)
        }
    }

    private func colorSwatchPicker(for row: FocusSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("점 색상")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 5),
                spacing: 8
            ) {
                swatch(
                    color: Constants.categoryColor(for: row.category),
                    selected: row.markerColorKey == nil,
                    isDefault: true
                ) { setMarkerColor(nil, for: row) }
                ForEach(FocusMarkerPalette.colors) { item in
                    swatch(
                        color: item.color,
                        selected: row.markerColorKey == item.key,
                        isDefault: false
                    ) { setMarkerColor(item.key, for: row) }
                }
            }
            Text("점선 = 카테고리 기본색")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .padding(14)
        .frame(width: 208)
    }

    private func swatch(
        color: Color,
        selected: Bool,
        isDefault: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle().strokeBorder(
                        PopoverChrome.inkSecondary,
                        style: StrokeStyle(lineWidth: 1.5, dash: isDefault ? [3, 2] : [])
                    )
                    .opacity(isDefault ? 1 : 0.15)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(selected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(isDefault ? "카테고리 기본색" : "")
    }

    private func setMarkerColor(_ key: String?, for row: FocusSessionRow) {
        colorPickerSessionID = nil
        let id = row.id
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(descriptor).first else { return }
        session.markerColorKey = key
        try? modelContext.save()
        NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
    }

    private func sessionCard(_ row: FocusSessionRow) -> some View {
        let isSelected = selectedSessionID == row.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                colorSwatchButton(for: row)
                Text("\(row.emoji) \(row.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ratingDots(row.rating)
                Text("\(focusTimeFormatter.string(from: row.startedAt)) · \(row.durationSeconds / 60)분")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }

            ViewThatFits(in: .horizontal) {
                sessionMetricRow(row)
                sessionMetricRow(row, wrap: true)
            }
        }
        .padding(12)
        .background(
            isSelected ? PopoverChrome.selectionFill.opacity(0.25) : PopoverChrome.card,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? PopoverChrome.accent : PopoverChrome.divider,
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSessionID = isSelected ? nil : row.id
        }
    }

    @ViewBuilder
    private func sessionMetricRow(_ row: FocusSessionRow, wrap: Bool = false) -> some View {
        let items: [(String, Bool)] = {
            var result: [(String, Bool)] = [
                ("연속 \(Int(row.continuousFocusMinutes))분", false),
                ("전환 \(row.observation.appSwitchCount)회", false),
                ("앱 \(row.appCount)개", false),
                ("활성 \(Int((row.activeRatio * 100).rounded()))%", false),
            ]
            if let mps = row.minutesPerSwitch {
                result.append(("전환당 \(String(format: "%.1f", mps))분", false))
            }
            if let pct = row.inputActivityPercent {
                result.append(("입력 \(pct)%", false))
            } else {
                result.append(("입력 —", true))
            }
            result.append(("휴식 준비 중", true))
            return result
        }()

        if wrap {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    metricLabel(item.0, pending: item.1)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    metricLabel(item.0, pending: item.1)
                }
            }
        }
    }

    private func metricLabel(_ text: String, pending: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(pending ? PopoverChrome.inkTertiary : PopoverChrome.inkSecondary)
            .monospacedDigit()
    }

    private func ratingDots(_ rating: Int?) -> some View {
        HStack(spacing: 3) {
            if let rating {
                ForEach(1...4, id: \.self) { index in
                    Circle()
                        .fill(index <= rating ? PopoverChrome.accent : PopoverChrome.divider)
                        .frame(width: 7, height: 7)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
    }
}
