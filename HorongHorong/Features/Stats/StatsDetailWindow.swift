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
                                taskCompletions: pomodoroTaskCompletions,
                                viewMode: viewMode,
                                referenceDate: selectedDate,
                                onNavigate: { mode, date in
                                    selectedDate = date
                                    viewMode = mode
                                }
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
            for: fetchedSessions
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
        for sessions: [FocusSession]
    ) -> [PomodoroTaskCompletion] {
        guard !sessions.isEmpty else { return [] }
        let sessionIDs = sessions.map(\.id)
        let descriptor = FetchDescriptor<PomodoroTaskCompletion>(
            predicate: #Predicate { sessionIDs.contains($0.focusSessionID) },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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

/// 몰입 지도 가로축 후보. `키보드·마우스 사용률`은 해당 데이터가 있는 세션만 표시한다.
enum FocusSessionMetric: String, CaseIterable, Identifiable {
    case continuousFocus
    case appSwitches
    case inputActivity
    case appCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuousFocus: return "한 곳 최장 사용"
        case .appSwitches: return "전환 횟수"
        case .inputActivity: return "키보드·마우스 사용률"
        case .appCount: return "사용한 앱·웹 수"
        }
    }

    var axisLabel: String {
        switch self {
        case .continuousFocus: return "한 곳 최장 사용 (분) →"
        case .appSwitches: return "전환 횟수 (회) →"
        case .inputActivity: return "키보드·마우스 사용률 (%) →"
        case .appCount: return "사용한 앱·웹 수 (개) →"
        }
    }

    var isAvailable: Bool { true }

    func value(_ row: FocusSessionRow) -> Double {
        switch self {
        case .continuousFocus: return row.continuousFocusMinutes
        case .appSwitches: return Double(row.observation.appSwitchCount)
        case .inputActivity: return (row.inputActivityRatio ?? 0) * 100
        case .appCount: return Double(row.appCount)
        }
    }

    /// 이 지표를 지도에 그릴 값이 있는지. 키보드·마우스 사용률은 수집된 세션만 그린다.
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

enum FocusSessionCompletionStatus: Equatable {
    case completedAsPlanned
    case endedEarly
    case unknown

    var label: String {
        switch self {
        case .completedAsPlanned: return "예정된 종료"
        case .endedEarly: return "조기 종료"
        case .unknown: return "종료 방식 미기록"
        }
    }

    var help: String {
        switch self {
        case .completedAsPlanned:
            return "처음 설정한 시간이 모두 지난 뒤 종료된 세션이에요."
        case .endedEarly:
            return "처음 설정한 시간이 끝나기 전에 기록 후 종료한 세션이에요."
        case .unknown:
            return "종료 방식 기록 기능이 생기기 전의 세션이거나 종료 방식을 확인할 수 없는 기록이에요."
        }
    }
}

struct FocusSessionRow: Identifiable {
    let id: UUID
    let linkedMemoID: UUID?
    let title: String
    let category: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let plannedDurationSeconds: Int?
    let endKind: FocusSessionEndKind?
    let rating: Int?
    let selfAssessmentLabel: String?
    let progressResult: PomodoroProgressResult?
    let incompleteReason: PomodoroIncompleteReason?
    let observation: PomodoroSessionObservation
    let inputActivityRatio: Double?
    let markerColorKey: String?
    var reflectionDeferredAt: Date? = nil

    var inputActivityPercent: Int? {
        inputActivityRatio.map { Int(($0 * 100).rounded()) }
    }

    var continuousFocusMinutes: Double {
        Double(observation.longestContinuousAppUsage?.durationSeconds ?? 0) / 60
    }
    var appUsageRatio: Double {
        observation.sessionSeconds > 0
            ? Double(observation.recordedSeconds) / Double(observation.sessionSeconds)
            : 0
    }
    var averageAppSwitchIntervalSeconds: Double? {
        observation.averageAppUsageRunSeconds
    }
    var completionStatus: FocusSessionCompletionStatus {
        switch endKind {
        case .timerCompleted:
            return .completedAsPlanned
        case .recordedEarly:
            return .endedEarly
        case nil:
            guard let plannedDurationSeconds,
                  plannedDurationSeconds > 0,
                  durationSeconds >= plannedDurationSeconds else {
                return .unknown
            }
            return .completedAsPlanned
        }
    }
    var appCount: Int { observation.distinctAppWebCount }
    var unclassifiedAppCount: Int {
        observation.apps.filter { $0.category == Constants.unclassifiedAppCategory }.count
    }
    var hasComparableRecord: Bool { observation.recordedSeconds > 0 }
    var color: Color {
        FocusMarkerPalette.color(forKey: markerColorKey) ?? Constants.categoryColor(for: category)
    }
    var emoji: String { Constants.categoryEmoji(for: category) }
    var isReflectionPending: Bool {
        reflectionDeferredAt != nil && selfAssessmentLabel == nil
    }
}

struct FocusCategorySummary: Identifiable, Equatable {
    var id: String { category }
    let category: String
    let durationSeconds: Int
    let sessionCount: Int
}

enum FocusCategorySummaryBuilder {
    static func summaries(rows: [FocusSessionRow]) -> [FocusCategorySummary] {
        let grouped = Dictionary(grouping: rows, by: \.category)
        return grouped.map { category, categoryRows in
            FocusCategorySummary(
                category: category,
                durationSeconds: categoryRows.reduce(0) { $0 + $1.durationSeconds },
                sessionCount: categoryRows.count
            )
        }
        .sorted {
            if $0.durationSeconds != $1.durationSeconds {
                return $0.durationSeconds > $1.durationSeconds
            }
            return $0.category < $1.category
        }
    }
}

enum FocusPeriodCalendarBuilder {
    static func weekDates(
        containing date: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let start = Constants.mondayWeekStart(for: date, calendar: calendar)
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    static func monthWeeks(
        containing date: Date,
        calendar: Calendar = .current
    ) -> [[Date?]] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ),
        let monthEnd = calendar.date(
            byAdding: .month,
            value: 1,
            to: monthStart
        ) else {
            return []
        }

        let leadingEmptyCount = mondayIndex(
            for: monthStart,
            calendar: calendar
        )
        var cells = Array<Date?>(repeating: nil, count: leadingEmptyCount)
        var cursor = monthStart
        while cursor < monthEnd {
            cells.append(cursor)
            guard let next = calendar.date(
                byAdding: .day,
                value: 1,
                to: cursor
            ) else {
                break
            }
            cursor = next
        }
        while cells.count.isMultiple(of: 7) == false {
            cells.append(nil)
        }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    static func mondayIndex(
        for date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}

struct FocusTaskSessionGroup: Identifiable {
    let id: String
    let linkedMemoID: UUID?
    let title: String
    let rows: [FocusSessionRow]
    let completedInPeriod: Bool

    var totalDurationSeconds: Int {
        rows.reduce(0) { $0 + $1.durationSeconds }
    }

    var completedAsPlannedCount: Int {
        rows.filter { $0.completionStatus == .completedAsPlanned }.count
    }

    var endedEarlyCount: Int {
        rows.filter { $0.completionStatus == .endedEarly }.count
    }

    var unknownEndCount: Int {
        rows.filter { $0.completionStatus == .unknown }.count
    }

    var categories: [String] {
        Array(Set(rows.map(\.category))).sorted()
    }

    var assessmentCounts: [(label: String, count: Int)] {
        let labels = rows.compactMap(\.selfAssessmentLabel)
        return PomodoroFocusExperience.allCases.compactMap { experience in
            let count = labels.filter { $0 == experience.label }.count
            return count > 0 ? (experience.label, count) : nil
        }
    }

    var pendingReflectionCount: Int {
        rows.filter(\.isReflectionPending).count
    }
}

enum FocusTaskSessionGroupBuilder {
    static func groups(
        rows: [FocusSessionRow],
        completedSessionIDs: Set<UUID>
    ) -> [FocusTaskSessionGroup] {
        let grouped = Dictionary(grouping: rows) { row in
            row.linkedMemoID.map { "task:\($0.uuidString)" }
                ?? "session:\(row.id.uuidString)"
        }

        return grouped.map { id, groupedRows in
            let sortedRows = groupedRows.sorted { $0.startedAt < $1.startedAt }
            return FocusTaskSessionGroup(
                id: id,
                linkedMemoID: sortedRows.first?.linkedMemoID,
                title: sortedRows.last?.title ?? "이름 없는 할 일",
                rows: sortedRows,
                completedInPeriod: sortedRows.contains {
                    completedSessionIDs.contains($0.id)
                }
            )
        }
        .sorted {
            ($0.rows.last?.startedAt ?? .distantPast)
                > ($1.rows.last?.startedAt ?? .distantPast)
        }
    }
}

struct FocusTaskSessionTrendPoint: Identifiable, Equatable {
    let id: UUID
    let iteration: Int
    let startedAt: Date
    let endedAt: Date
    let completionStatus: FocusSessionCompletionStatus
    let selfAssessmentLabel: String?
    let selfAssessmentRating: Int?
    let progressResult: PomodoroProgressResult?
    let incompleteReason: PomodoroIncompleteReason?
    let taskCompleted: Bool

    var progressScore: Double? {
        switch progressResult {
        case .littleProgress: return 1
        case .meaningfulProgress: return 2
        case .completedAsPlanned: return 3
        case .goalChanged, .none: return nil
        }
    }

    var focusScore: Double? {
        selfAssessmentRating.map(Double.init)
    }

    var canPlotOnCauseMap: Bool {
        focusScore != nil && progressScore != nil
    }
}

enum FocusTaskSessionTrendBuilder {
    static func points(
        rows: [FocusSessionRow],
        completedSessionIDs: Set<UUID> = []
    ) -> [FocusTaskSessionTrendPoint] {
        rows
            .sorted { $0.startedAt < $1.startedAt }
            .enumerated()
            .map { offset, row in
                FocusTaskSessionTrendPoint(
                    id: row.id,
                    iteration: offset + 1,
                    startedAt: row.startedAt,
                    endedAt: row.endedAt,
                    completionStatus: row.completionStatus,
                    selfAssessmentLabel: row.selfAssessmentLabel,
                    selfAssessmentRating: row.rating,
                    progressResult: row.progressResult,
                    incompleteReason: row.incompleteReason,
                    taskCompleted: completedSessionIDs.contains(row.id)
                )
            }
    }
}

enum FocusTaskContinuationCause: String, CaseIterable, Identifiable {
    case scopeOrQuality
    case difficultyOrBlocked
    case focusDisruption
    case contextChange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scopeOrQuality: return "작업 범위·완성도"
        case .difficultyOrBlocked: return "막힘·난이도"
        case .focusDisruption: return "집중 방해"
        case .contextChange: return "외부·방향 변경"
        }
    }

    var shortTitle: String {
        switch self {
        case .scopeOrQuality: return "분량·범위 단서"
        case .difficultyOrBlocked: return "막힘·난이도 단서"
        case .focusDisruption: return "집중 어려움 단서"
        case .contextChange: return "외부·방향 변경"
        }
    }
}

struct FocusTaskContinuationCauseEvidence: Identifiable, Equatable {
    var id: FocusTaskContinuationCause { cause }
    let cause: FocusTaskContinuationCause
    let directSessionCount: Int
    let supportingSessionCount: Int
}

struct FocusTaskContinuationCauseSummary: Equatable {
    let evidence: [FocusTaskContinuationCauseEvidence]
    let dominantCause: FocusTaskContinuationCause?
    let headline: String
}

enum FocusTaskContinuationCauseBuilder {
    static func summary(
        points: [FocusTaskSessionTrendPoint]
    ) -> FocusTaskContinuationCauseSummary {
        var directSessionIDs = Dictionary(
            uniqueKeysWithValues: FocusTaskContinuationCause.allCases.map {
                ($0, Set<UUID>())
            }
        )
        var supportingSessionIDs = directSessionIDs

        for point in points {
            let directCause = directCause(for: point)
            if let directCause {
                directSessionIDs[directCause, default: []].insert(point.id)
            }
            for cause in supportingCauses(for: point) where cause != directCause {
                supportingSessionIDs[cause, default: []].insert(point.id)
            }
        }

        let evidence = FocusTaskContinuationCause.allCases.map { cause in
            FocusTaskContinuationCauseEvidence(
                cause: cause,
                directSessionCount: directSessionIDs[cause]?.count ?? 0,
                supportingSessionCount: supportingSessionIDs[cause]?.count ?? 0
            )
        }
        let highestDirectCount = evidence.map(\.directSessionCount).max() ?? 0
        let strongestDirectCauses = evidence.filter {
            highestDirectCount > 0 && $0.directSessionCount == highestDirectCount
        }
        let dominantCause = strongestDirectCauses.count == 1
            ? strongestDirectCauses[0].cause
            : nil
        let totalSupportingCount = evidence.reduce(0) {
            $0 + $1.supportingSessionCount
        }

        let headline: String
        if let dominantCause {
            headline = "가장 강한 단서: \(dominantCause.title)"
        } else if strongestDirectCauses.count > 1 {
            headline = "여러 이유가 함께 기록됐어요"
        } else if totalSupportingCount > 0 {
            headline = "직접 선택한 이유가 없어 응답 조합만 보여드려요"
        } else {
            headline = "이유를 판단할 회고가 부족해요"
        }

        return FocusTaskContinuationCauseSummary(
            evidence: evidence,
            dominantCause: dominantCause,
            headline: headline
        )
    }

    static func directCause(
        for point: FocusTaskSessionTrendPoint
    ) -> FocusTaskContinuationCause? {
        if let reason = point.incompleteReason {
            switch reason {
            case .insufficientTime, .underestimatedScope, .continuedForQuality:
                return .scopeOrQuality
            case .blocked:
                return .difficultyOrBlocked
            case .distracted:
                return .focusDisruption
            case .switchedTask, .externalInterruption:
                return .contextChange
            }
        }
        if point.progressResult == .goalChanged {
            return .contextChange
        }
        return nil
    }

    static func supportingCauses(
        for point: FocusTaskSessionTrendPoint
    ) -> Set<FocusTaskContinuationCause> {
        guard point.progressResult != .completedAsPlanned,
              point.progressResult != .goalChanged else {
            return []
        }

        var causes: Set<FocusTaskContinuationCause> = []
        if let rating = point.selfAssessmentRating {
            if rating <= 2 {
                causes.insert(.focusDisruption)
            } else if point.progressResult == .littleProgress {
                causes.insert(.difficultyOrBlocked)
            } else if point.progressResult == .meaningfulProgress {
                causes.insert(.scopeOrQuality)
            }
        }
        return causes
    }
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
‘잘 모르겠어요’는 차트에서 빼요
"""

private struct FocusCauseMapRouteNode: Identifiable {
    var id: UUID { point.id }
    let point: FocusTaskSessionTrendPoint
    let x: Double
    let y: Double
    let usesDetourLane: Bool
}

private struct FocusCauseMapRouteSegment: Identifiable {
    var id: String {
        "\(start.id.uuidString)-\(end.id.uuidString)"
    }
    let start: FocusCauseMapRouteNode
    let end: FocusCauseMapRouteNode

    var usesDetourLane: Bool {
        start.usesDetourLane || end.usesDetourLane
    }
}

private struct FocusTaskSessionTrendView: View {
    let points: [FocusTaskSessionTrendPoint]
    @Binding var selectedSessionID: UUID?
    @Binding var hoveredSessionID: UUID?

    private var activePoint: FocusTaskSessionTrendPoint? {
        let activeID = hoveredSessionID ?? selectedSessionID
        return activeID.flatMap { id in points.first { $0.id == id } }
    }

    private var causeSummary: FocusTaskContinuationCauseSummary {
        FocusTaskContinuationCauseBuilder.summary(points: points)
    }

    private var mappablePoints: [FocusTaskSessionTrendPoint] {
        points.filter(\.canPlotOnCauseMap)
    }

    private var causeMapRouteNodes: [FocusCauseMapRouteNode] {
        let lastIndex = max(1, points.count - 1)
        return points.enumerated().map { index, point in
            if let position = causeMapPosition(for: point) {
                return FocusCauseMapRouteNode(
                    point: point,
                    x: position.x,
                    y: position.y,
                    usesDetourLane: false
                )
            }
            let timelineX = points.count == 1
                ? 2.5
                : 0.75 + Double(index) / Double(lastIndex) * 3.5
            return FocusCauseMapRouteNode(
                point: point,
                x: timelineX,
                y: 0,
                usesDetourLane: true
            )
        }
    }

    private var causeMapRouteSegments: [FocusCauseMapRouteSegment] {
        zip(causeMapRouteNodes, causeMapRouteNodes.dropFirst()).map {
            FocusCauseMapRouteSegment(start: $0.0, end: $0.1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("왜 여러 회차가 필요했을까요?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                Text("회고 응답을 먼저 보고, 패턴 추정은 보조로만 사용해요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Spacer()
                Text("\(points.count)회차")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }

            causeOverview
            causeMapPanel

            Text("회차별 기록")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PopoverChrome.inkTertiary)
            sessionContextStrip
        }
        .padding(12)
        .background(
            PopoverChrome.card.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.divider, lineWidth: 1)
        )
        .onDisappear {
            if let hoveredSessionID,
               points.contains(where: { $0.id == hoveredSessionID }) {
                self.hoveredSessionID = nil
            }
        }
    }

    private var causeOverview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(causeSummary.headline)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("● 회고 응답  ○ 패턴 추정")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(causeSummary.evidence) { evidence in
                    causeEvidenceCard(evidence)
                }
            }
        }
        .padding(10)
        .background(
            PopoverChrome.surface,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private func causeEvidenceCard(
        _ evidence: FocusTaskContinuationCauseEvidence
    ) -> some View {
        let highlighted = causeSummary.dominantCause == evidence.cause
        let hasEvidence = evidence.directSessionCount > 0
            || evidence.supportingSessionCount > 0
        let tint = causeTint(evidence.cause)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: causeIcon(evidence.cause))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasEvidence ? tint : PopoverChrome.inkTertiary)
                Text(evidence.cause.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        hasEvidence ? PopoverChrome.ink : PopoverChrome.inkTertiary
                    )
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("● 응답 \(evidence.directSessionCount)회")
                Text("○ 추정 \(evidence.supportingSessionCount)회")
            }
            .font(.caption2)
            .foregroundStyle(
                hasEvidence ? PopoverChrome.inkSecondary : PopoverChrome.inkTertiary
            )
            .monospacedDigit()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlighted ? tint.opacity(0.12) : PopoverChrome.card,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    highlighted ? tint : PopoverChrome.divider,
                    lineWidth: highlighted ? 1.5 : 1
                )
        )
        .help(
            "● 응답은 회고에서 고른 이유이고, ○ 추정은 집중 체감과 진척 결과의 조합에서 보이는 패턴입니다."
        )
    }

    private var causeMapPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("집중 체감 × 작업 진척")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                Text("아래로 우회하는 선은 위치를 알 수 없는 회차예요")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Spacer()
            }

            causeMapChart

            let excluded = points.filter { !$0.canPlotOnCauseMap }
            if !excluded.isEmpty {
                Text(
                    "알 수 없음: "
                    + excluded.map(mapExclusionText).joined(separator: " · ")
                )
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            PopoverChrome.surface,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var causeMapChart: some View {
        Chart {
            RectangleMark(
                xStart: .value("집중 시작", 0.5),
                xEnd: .value("집중 끝", 2.5),
                yStart: .value("진척 시작", 0.5),
                yEnd: .value("진척 끝", 2.5)
            )
            .foregroundStyle(causeTint(.focusDisruption).opacity(0.08))
            .annotation(position: .overlay) {
                causeZoneLabel(.focusDisruption)
            }

            RectangleMark(
                xStart: .value("난이도 시작", 2.5),
                xEnd: .value("난이도 끝", 4.5),
                yStart: .value("진척 시작", 0.5),
                yEnd: .value("진척 끝", 1.5)
            )
            .foregroundStyle(causeTint(.difficultyOrBlocked).opacity(0.08))
            .annotation(position: .overlay) {
                causeZoneLabel(.difficultyOrBlocked)
            }

            RectangleMark(
                xStart: .value("범위 시작", 2.5),
                xEnd: .value("범위 끝", 4.5),
                yStart: .value("진척 시작", 1.5),
                yEnd: .value("진척 끝", 2.5)
            )
            .foregroundStyle(causeTint(.scopeOrQuality).opacity(0.08))
            .annotation(position: .overlay) {
                causeZoneLabel(.scopeOrQuality)
            }

            RectangleMark(
                xStart: .value("완료 시작", 0.5),
                xEnd: .value("완료 끝", 4.5),
                yStart: .value("진척 시작", 2.5),
                yEnd: .value("진척 끝", 3.5)
            )
            .foregroundStyle(Color.green.opacity(0.08))
            .annotation(position: .overlay) {
                Text("계획한 만큼 완료")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.green.opacity(0.75))
            }

            RectangleMark(
                xStart: .value("우회 시작", 0.5),
                xEnd: .value("우회 끝", 4.5),
                yStart: .value("우회 아래", -0.4),
                yEnd: .value("우회 위", 0.4)
            )
            .foregroundStyle(PopoverChrome.inkTertiary.opacity(0.07))

            RuleMark(y: .value("알 수 없음 구분", 0.4))
                .foregroundStyle(PopoverChrome.divider)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(causeMapRouteSegments) { segment in
                LineMark(
                    x: .value("경로 시작 X", segment.start.x),
                    y: .value("경로 시작 Y", segment.start.y),
                    series: .value("경로 구간", segment.id)
                )
                .foregroundStyle(PopoverChrome.inkTertiary.opacity(0.58))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 1.5,
                        dash: segment.usesDetourLane ? [4, 3] : []
                    )
                )
                LineMark(
                    x: .value("경로 끝 X", segment.end.x),
                    y: .value("경로 끝 Y", segment.end.y),
                    series: .value("경로 구간", segment.id)
                )
                .foregroundStyle(PopoverChrome.inkTertiary.opacity(0.58))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 1.5,
                        dash: segment.usesDetourLane ? [4, 3] : []
                    )
                )
            }

            ForEach(causeMapRouteNodes) { node in
                PointMark(
                    x: .value("집중 체감", node.x),
                    y: .value("작업 진척", node.y)
                )
                .symbolSize(activePoint?.id == node.id ? 190 : 145)
                .foregroundStyle(
                    node.usesDetourLane
                        ? PopoverChrome.inkTertiary
                        : pointTint(node.point)
                )
                .opacity(activePoint == nil || activePoint?.id == node.id ? 1 : 0.38)
                .annotation(position: .overlay) {
                    Text("\(node.point.iteration)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .chartXScale(domain: 0.5...4.5)
        .chartYScale(domain: -0.4...3.5)
        .chartXAxis {
            AxisMarks(values: [1.0, 2.0, 3.0, 4.0]) { value in
                AxisGridLine()
                    .foregroundStyle(PopoverChrome.divider.opacity(0.55))
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text(focusAxisLabel(Int(score.rounded())))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 1.0, 2.0, 3.0]) { value in
                AxisGridLine()
                    .foregroundStyle(PopoverChrome.divider.opacity(0.55))
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text(progressAxisLabel(Int(score.rounded())))
                    }
                }
            }
        }
        .chartXAxisLabel("내가 느낀 집중 →", alignment: .trailing)
        .frame(height: 285)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                causeMapInteractionLayer(proxy: proxy, geometry: geometry)
            }
        }
    }

    private func causeZoneLabel(
        _ cause: FocusTaskContinuationCause
    ) -> some View {
        Text(cause.shortTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(causeTint(cause).opacity(0.7))
    }

    private func causeMapInteractionLayer(
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredSessionID = nearestCauseMapPoint(
                        to: location,
                        proxy: proxy,
                        geometry: geometry
                    )?.id
                case .ended:
                    hoveredSessionID = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { event in
                    guard let point = nearestCauseMapPoint(
                        to: event.location,
                        proxy: proxy,
                        geometry: geometry
                    ) else { return }
                    selectedSessionID = selectedSessionID == point.id ? nil : point.id
                }
            )
    }

    private func nearestCauseMapPoint(
        to location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> FocusTaskSessionTrendPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        let relativePoint = CGPoint(
            x: location.x - frame.minX,
            y: location.y - frame.minY
        )
        var nearest: (point: FocusTaskSessionTrendPoint, distance: CGFloat)?
        for node in causeMapRouteNodes {
            guard let x = proxy.position(forX: node.x),
                  let y = proxy.position(forY: node.y) else {
                continue
            }
            let distance = hypot(x - relativePoint.x, y - relativePoint.y)
            if nearest == nil || distance < nearest!.distance {
                nearest = (node.point, distance)
            }
        }
        guard let nearest, nearest.distance < 42 else { return nil }
        return nearest.point
    }

    private var sessionContextStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    sessionContextButton(point)
                    if index < points.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func sessionContextButton(
        _ point: FocusTaskSessionTrendPoint
    ) -> some View {
        let active = activePoint?.id == point.id
        let tint = completionTint(point.completionStatus)
        let supportingCause = FocusTaskContinuationCauseBuilder
            .supportingCauses(for: point)
            .first
        return Button {
            selectedSessionID = selectedSessionID == point.id ? nil : point.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text("\(point.iteration)회차")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.ink)
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                    Text(point.completionStatus.label)
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    Spacer(minLength: 4)
                    if point.taskCompleted {
                        Text("할 일 완료")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PopoverChrome.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                PopoverChrome.accent.opacity(0.1),
                                in: Capsule()
                            )
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: point.selfAssessmentRating == nil ? "circle.dashed" : "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(assessmentTint(point.selfAssessmentRating))
                    Text(point.selfAssessmentLabel ?? "자기평가 없음")
                        .font(.caption2)
                        .foregroundStyle(
                            point.selfAssessmentLabel == nil
                                ? PopoverChrome.inkTertiary
                                : PopoverChrome.inkSecondary
                        )
                        .lineLimit(1)
                }
                Divider()
                Text(
                    point.progressResult?.label(
                        recordsLinkedTaskCompletion: point.taskCompleted
                    ) ?? "작업 진척 회고 없음"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(
                    point.progressResult == nil
                        ? PopoverChrome.inkTertiary
                        : PopoverChrome.inkSecondary
                )
                .lineLimit(1)
                if let reason = point.incompleteReason {
                    Label {
                        Text(reason.label)
                            .lineLimit(2)
                    } icon: {
                        Text("●")
                            .foregroundStyle(
                                causeTint(
                                    FocusTaskContinuationCauseBuilder.directCause(
                                        for: point
                                    ) ?? .contextChange
                                )
                            )
                    }
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                } else if let supportingCause {
                    Text("○ \(supportingCause.shortTitle)")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(width: 220, alignment: .leading)
            .frame(minHeight: 108, alignment: .topLeading)
            .background(
                active ? PopoverChrome.selectionFill : PopoverChrome.surface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        active ? PopoverChrome.accent : PopoverChrome.divider,
                        lineWidth: active ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredSessionID = point.id
            } else if hoveredSessionID == point.id {
                hoveredSessionID = nil
            }
        }
        .help(sessionIdentityText(point))
    }

    private func sessionIdentityText(
        _ point: FocusTaskSessionTrendPoint
    ) -> String {
        let timeRange = "\(focusTimeFormatter.string(from: point.startedAt))–\(focusTimeFormatter.string(from: point.endedAt))"
        let assessment = point.selfAssessmentLabel ?? "자기평가 없음"
        let progress = point.progressResult?.label(
            recordsLinkedTaskCompletion: point.taskCompleted
        ) ?? "작업 진척 회고 없음"
        var parts = [
            "\(point.iteration)회차",
            timeRange,
            point.completionStatus.label,
            assessment,
            progress,
        ]
        if let reason = point.incompleteReason {
            parts.append(reason.label)
        }
        return parts.joined(separator: " · ")
    }

    private func assessmentTint(_ rating: Int?) -> Color {
        switch rating {
        case 4: return PopoverChrome.accent
        case 3: return .green
        case 2: return .orange
        case 1: return .red
        default: return PopoverChrome.inkTertiary
        }
    }

    private func completionTint(
        _ status: FocusSessionCompletionStatus
    ) -> Color {
        switch status {
        case .completedAsPlanned: return PopoverChrome.accent
        case .endedEarly: return .orange
        case .unknown: return PopoverChrome.inkTertiary
        }
    }

    private func causeTint(
        _ cause: FocusTaskContinuationCause
    ) -> Color {
        switch cause {
        case .scopeOrQuality: return .blue
        case .difficultyOrBlocked: return .purple
        case .focusDisruption: return .red
        case .contextChange: return PopoverChrome.inkSecondary
        }
    }

    private func causeIcon(
        _ cause: FocusTaskContinuationCause
    ) -> String {
        switch cause {
        case .scopeOrQuality: return "shippingbox"
        case .difficultyOrBlocked: return "exclamationmark.triangle"
        case .focusDisruption: return "scope"
        case .contextChange: return "arrow.triangle.branch"
        }
    }

    private func pointTint(
        _ point: FocusTaskSessionTrendPoint
    ) -> Color {
        if point.progressResult == .completedAsPlanned {
            return .green
        }
        if let cause = FocusTaskContinuationCauseBuilder.directCause(for: point) {
            return causeTint(cause)
        }
        if let cause = FocusTaskContinuationCauseBuilder
            .supportingCauses(for: point)
            .first {
            return causeTint(cause)
        }
        return PopoverChrome.accent
    }

    private func causeMapPosition(
        for point: FocusTaskSessionTrendPoint
    ) -> (x: Double, y: Double)? {
        guard let focusScore = point.focusScore,
              let progressScore = point.progressScore else {
            return nil
        }
        let overlappingPoints = mappablePoints.filter {
            $0.focusScore == focusScore && $0.progressScore == progressScore
        }
        guard overlappingPoints.count > 1,
              let index = overlappingPoints.firstIndex(where: { $0.id == point.id }) else {
            return (focusScore, progressScore)
        }
        let offset = Double(index) / Double(overlappingPoints.count - 1) * 0.44 - 0.22
        return (focusScore + offset, progressScore)
    }

    private func focusAxisLabel(
        _ score: Int
    ) -> String {
        switch score {
        case 1: return "어려움"
        case 2: return "흐트러짐"
        case 3: return "대체로"
        case 4: return "깊게"
        default: return ""
        }
    }

    private func progressAxisLabel(
        _ score: Int
    ) -> String {
        switch score {
        case 0: return "알 수 없음"
        case 1: return "거의 못함"
        case 2: return "의미 있게"
        case 3: return "계획만큼"
        default: return ""
        }
    }

    private func mapExclusionText(
        _ point: FocusTaskSessionTrendPoint
    ) -> String {
        let focus = point.selfAssessmentLabel ?? "집중 회고 없음"
        let progress = point.progressResult?.label(
            recordsLinkedTaskCompletion: point.taskCompleted
        ) ?? "진척 회고 없음"
        return "\(point.iteration)회차 · 집중 체감: \(focus) · 작업 진척: \(progress)"
    }

}

private struct WeeklyFocusPlotPoint: Identifiable {
    var id: UUID { row.id }
    let row: FocusSessionRow
    let plotDate: Date
    let focusLevel: Int
}

private struct FocusResponseBucket: Identifiable {
    let id: Int
    let label: String
    let color: Color
}

struct FocusDetailView: View {
    let sessions: [PomodoroSessionBreakdown]
    let reflections: [PomodoroReflection]
    let taskCompletions: [PomodoroTaskCompletion]
    let viewMode: StatsViewMode
    let referenceDate: Date
    let onNavigate: (StatsViewMode, Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var xMetric: FocusSessionMetric = .continuousFocus
    @State private var selectedSessionID: UUID?
    @State private var showsScoreInfo = false
    @State private var showsSessionMetricInfo = false
    @State private var colorPickerSessionID: UUID?
    @State private var selectedCategory: String?
    @State private var showsCategoryFilter = false
    @State private var categorySearchText = ""
    @State private var expandedTaskGroupIDs: Set<String> = []
    @State private var hoveredTaskSessionID: UUID?

    private var rows: [FocusSessionRow] {
        let reflectionByID = Dictionary(
            reflections.map { ($0.focusSessionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions.map { session in
            let reflection = reflectionByID[session.id]
            return FocusSessionRow(
                id: session.id,
                linkedMemoID: session.linkedMemoID,
                title: session.taskTitle ?? "\(session.category) 세션",
                category: session.category,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                durationSeconds: session.durationSeconds,
                plannedDurationSeconds: session.plannedDurationSeconds,
                endKind: session.endKind,
                rating: focusRating(reflection?.focusExperience),
                selfAssessmentLabel: reflection?.focusExperience?.label,
                progressResult: reflection?.progressResult,
                incompleteReason: reflection?.incompleteReason,
                observation: session.observation,
                inputActivityRatio: session.inputActivityRatio,
                markerColorKey: session.markerColorKey,
                reflectionDeferredAt: session.reflectionDeferredAt
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    private var categorySummaries: [FocusCategorySummary] {
        FocusCategorySummaryBuilder.summaries(rows: rows)
    }

    private var filteredRows: [FocusSessionRow] {
        guard let selectedCategory else { return rows }
        return rows.filter { $0.category == selectedCategory }
    }

    private var mapRows: [FocusSessionRow] {
        filteredRows.filter { $0.rating != nil && $0.hasComparableRecord }
    }

    private var pendingReflectionRows: [FocusSessionRow] {
        filteredRows
            .filter(\.isReflectionPending)
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// 선택한 가로축 지표로 실제 그릴 수 있는 세션(예: 키보드·마우스 사용률은 수집된 세션만).
    private var plottedRows: [FocusSessionRow] {
        mapRows.filter { xMetric.hasValue($0) }
    }

    private var selectedRow: FocusSessionRow? {
        selectedSessionID.flatMap { id in filteredRows.first { $0.id == id } }
    }

    private var taskGroups: [FocusTaskSessionGroup] {
        FocusTaskSessionGroupBuilder.groups(
            rows: filteredRows,
            completedSessionIDs: completedTaskSessionIDs
        )
    }

    private var completedTaskSessionIDs: Set<UUID> {
        Set(taskCompletions.map(\.focusSessionID))
    }

    private var periodCalendar: Calendar {
        Calendar.current
    }

    private var weekDates: [Date] {
        FocusPeriodCalendarBuilder.weekDates(
            containing: referenceDate,
            calendar: periodCalendar
        )
    }

    private var monthWeeks: [[Date?]] {
        FocusPeriodCalendarBuilder.monthWeeks(
            containing: referenceDate,
            calendar: periodCalendar
        )
    }

    private var filteredRowsByDay: [Date: [FocusSessionRow]] {
        Dictionary(grouping: filteredRows) {
            periodCalendar.startOfDay(for: $0.startedAt)
        }
    }

    private var focusResponseBuckets: [FocusResponseBucket] {
        [
            FocusResponseBucket(id: 4, label: "깊게", color: PopoverChrome.accent),
            FocusResponseBucket(id: 3, label: "대체로", color: .green),
            FocusResponseBucket(id: 2, label: "흐트러짐", color: .orange),
            FocusResponseBucket(id: 1, label: "어려움", color: .red),
            FocusResponseBucket(
                id: 0,
                label: "알 수 없음",
                color: PopoverChrome.inkTertiary
            ),
        ]
    }

    private var weeklyPlotPoints: [WeeklyFocusPlotPoint] {
        let reflectedRows = filteredRows.filter {
            focusLevel(for: $0) != nil
        }
        let groupedRows = Dictionary(grouping: reflectedRows) { row in
            let day = periodCalendar.startOfDay(for: row.startedAt)
            return "\(day.timeIntervalSinceReferenceDate)-\(focusLevel(for: row) ?? -1)"
        }
        return groupedRows.values.flatMap { group in
            let sorted = group.sorted { $0.startedAt < $1.startedAt }
            let count = sorted.count
            return sorted.enumerated().map { index, row in
                let day = periodCalendar.startOfDay(for: row.startedAt)
                let center = Double(count - 1) / 2
                let spacingHours = min(1.6, 6 / Double(max(1, count)))
                let offsetHours = (Double(index) - center) * spacingHours
                let noon = periodCalendar.date(
                    byAdding: .hour,
                    value: 12,
                    to: day
                ) ?? day
                let plotDate = noon.addingTimeInterval(offsetHours * 3_600)
                return WeeklyFocusPlotPoint(
                    row: row,
                    plotDate: plotDate,
                    focusLevel: focusLevel(for: row) ?? 0
                )
            }
        }
        .sorted { $0.row.startedAt < $1.row.startedAt }
    }

    private var missingReflectionCount: Int {
        filteredRows.filter { $0.selfAssessmentLabel == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if rows.isEmpty {
                emptyState
            } else {
                categoryFilterSection
                if !pendingReflectionRows.isEmpty {
                    pendingReflectionBanner
                }
                if filteredRows.isEmpty {
                    filteredEmptyState
                } else {
                    periodFocusContent
                    taskGroupListSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: categorySummaries.map(\.category)) { _, categories in
            if let selectedCategory, !categories.contains(selectedCategory) {
                self.selectedCategory = nil
            }
        }
        .onChange(of: viewMode) { _, _ in
            selectedSessionID = nil
            hoveredTaskSessionID = nil
            expandedTaskGroupIDs.removeAll()
        }
    }

    @ViewBuilder
    private var periodFocusContent: some View {
        switch viewMode {
        case .daily:
            focusMapCard
        case .weekly:
            weeklyFocusCard
        case .monthly:
            monthlyFocusCalendarCard
            monthlyWeekdayPatternCard
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.largeTitle)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("이 기간에 기록된 포모도로가 없어요.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text("포모도로를 기록하면 카테고리와 할 일별로 묶어서 볼 수 있어요.")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var filteredEmptyState: some View {
        Text("선택한 카테고리에 표시할 포모도로가 없어요.")
            .font(.callout)
            .foregroundStyle(PopoverChrome.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private var pendingReflectionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("나중에 하기로 한 회고가 \(pendingReflectionRows.count)개 있어요")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                Text("가장 최근에 건너뛴 포모도로부터 이어서 작성할 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            Spacer(minLength: 8)

            if let row = pendingReflectionRows.first {
                Button("회고 작성") {
                    showReflection(for: row)
                }
                .buttonStyle(.borderedProminent)
                .tint(PopoverChrome.accent)
            }
        }
        .padding(12)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        )
    }

    // MARK: 카테고리 필터

    private var searchedCategorySummaries: [FocusCategorySummary] {
        let query = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categorySummaries }
        return categorySummaries.filter {
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    private var categoryFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("카테고리")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                categoryFilterButton
                Spacer()
                Text("현재 기간 · \(filteredRows.count)개 세션")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(categorySummaries.prefix(5)) { summary in
                    categorySummaryTile(summary)
                }
                if categorySummaries.count > 5 {
                    Button {
                        categorySearchText = ""
                        showsCategoryFilter = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "ellipsis")
                            Text("\(categorySummaries.count - 5)개 더보기")
                            Spacer(minLength: 0)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            PopoverChrome.surface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(PopoverChrome.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .popoverCard(padding: 12)
    }

    private var categoryFilterButton: some View {
        Button {
            categorySearchText = ""
            showsCategoryFilter.toggle()
        } label: {
            HStack(spacing: 6) {
                if let selectedCategory {
                    Circle()
                        .fill(Constants.categoryColor(for: selectedCategory))
                        .frame(width: 8, height: 8)
                }
                Text(selectedCategory ?? "전체 카테고리")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(PopoverChrome.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                PopoverChrome.surface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PopoverChrome.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsCategoryFilter) {
            categoryFilterPopover
        }
    }

    private var categoryFilterPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("카테고리 선택")
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)

            TextField("카테고리 검색", text: $categorySearchText)
                .textFieldStyle(.roundedBorder)

            Button {
                selectCategory(nil)
            } label: {
                categoryFilterRow(
                    title: "전체 카테고리",
                    color: nil,
                    detail: "\(rows.count)개 세션",
                    selected: selectedCategory == nil
                )
            }
            .buttonStyle(.plain)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(searchedCategorySummaries) { summary in
                        Button {
                            selectCategory(summary.category)
                        } label: {
                            categoryFilterRow(
                                title: summary.category,
                                color: Constants.categoryColor(for: summary.category),
                                detail: "\(summary.sessionCount)개 · \(formattedMetricDuration(Double(summary.durationSeconds)))",
                                selected: selectedCategory == summary.category
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func categoryFilterRow(
        title: String,
        color: Color?,
        detail: String,
        selected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color ?? PopoverChrome.inkTertiary)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(PopoverChrome.accent)
                .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(
            selected ? PopoverChrome.selectionFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func categorySummaryTile(_ summary: FocusCategorySummary) -> some View {
        let selected = selectedCategory == summary.category
        return Button {
            selectCategory(summary.category)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(Constants.categoryColor(for: summary.category))
                    .frame(width: 9, height: 9)
                Text(summary.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(formattedMetricDuration(Double(summary.durationSeconds)))
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                selected ? PopoverChrome.selectionFill : PopoverChrome.surface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        selected ? PopoverChrome.accent : PopoverChrome.divider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(summary.category) 카테고리만 봅니다")
    }

    private func selectCategory(_ category: String?) {
        selectedCategory = category
        selectedSessionID = nil
        showsCategoryFilter = false
        categorySearchText = ""
    }

    // MARK: 주간 몰입

    private var weeklyFocusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("요일별 몰입 흐름")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("점 하나는 포모도로 한 세션이에요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            weeklyProgressLegend

            if weeklyPlotPoints.isEmpty {
                Text("이번 주에는 집중 체감을 남긴 세션이 없어요.")
                    .font(.callout)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                weeklyFocusChart
            }

            if missingReflectionCount > 0 {
                Text("회고가 없는 \(missingReflectionCount)개 세션은 차트에서 제외했어요.")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            if let selectedRow {
                selectedDetailLine(selectedRow)
            }

            Divider()
            Text("날짜를 누르면 일간 몰입 기록으로 이동해요.")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
            weeklyDayNavigator
        }
        .popoverCard(padding: 16)
    }

    private var weeklyProgressLegend: some View {
        HStack(spacing: 12) {
            progressLegendItem(
                title: "계획만큼 완료",
                color: .green
            )
            progressLegendItem(
                title: "의미 있게 진행",
                color: .blue
            )
            progressLegendItem(
                title: "거의 못함",
                color: .red
            )
            progressLegendItem(
                title: "목표 변경·미기록",
                color: PopoverChrome.inkTertiary
            )
            Spacer(minLength: 0)
        }
    }

    private func progressLegendItem(
        title: String,
        color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
    }

    private var weeklyFocusChart: some View {
        let start = weekDates.first ?? referenceDate
        let end = periodCalendar.date(
            byAdding: .day,
            value: 7,
            to: start
        ) ?? start
        let axisDates = weekDates.map {
            periodCalendar.date(byAdding: .hour, value: 12, to: $0) ?? $0
        }
        return Chart(weeklyPlotPoints) { point in
            PointMark(
                x: .value("날짜", point.plotDate),
                y: .value("집중 체감", Double(point.focusLevel))
            )
            .symbolSize(selectedSessionID == point.id ? 125 : 82)
            .foregroundStyle(progressTint(point.row.progressResult))
            .opacity(
                selectedSessionID == nil || selectedSessionID == point.id
                    ? 0.9
                    : 0.3
            )
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: -0.4...4.5)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine()
                    .foregroundStyle(PopoverChrome.divider.opacity(0.65))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(weekdayDayText(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(
                position: .leading,
                values: [0.0, 1.0, 2.0, 3.0, 4.0]
            ) { value in
                AxisGridLine()
                    .foregroundStyle(PopoverChrome.divider.opacity(0.65))
                AxisValueLabel {
                    if let level = value.as(Double.self) {
                        Text(focusLevelLabel(Int(level.rounded())))
                    }
                }
            }
        }
        .frame(height: 300)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { event in
                            selectNearestWeeklyPoint(
                                to: event.location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        }
                    )
            }
        }
    }

    private var weeklyDayNavigator: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                let day = periodCalendar.startOfDay(for: date)
                let count = filteredRowsByDay[day]?.count ?? 0
                Button {
                    onNavigate(.daily, date)
                } label: {
                    VStack(spacing: 3) {
                        Text(weekdayDayText(date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PopoverChrome.ink)
                        Text(count == 0 ? "기록 없음" : "\(count)회")
                            .font(.caption2)
                            .foregroundStyle(
                                count == 0
                                    ? PopoverChrome.inkTertiary
                                    : PopoverChrome.inkSecondary
                            )
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        count > 0
                            ? PopoverChrome.selectionFill.opacity(0.45)
                            : PopoverChrome.surface,
                        in: RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                        .stroke(PopoverChrome.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectNearestWeeklyPoint(
        to location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let relativePoint = CGPoint(
            x: location.x - frame.minX,
            y: location.y - frame.minY
        )
        var nearest: (id: UUID, distance: CGFloat)?
        for point in weeklyPlotPoints {
            guard let x = proxy.position(forX: point.plotDate),
                  let y = proxy.position(forY: Double(point.focusLevel)) else {
                continue
            }
            let distance = hypot(x - relativePoint.x, y - relativePoint.y)
            if nearest == nil || distance < nearest!.distance {
                nearest = (point.id, distance)
            }
        }
        if let nearest, nearest.distance < 44 {
            selectedSessionID = selectedSessionID == nearest.id
                ? nil
                : nearest.id
        } else {
            selectedSessionID = nil
        }
    }

    // MARK: 월간 몰입

    private var monthlyFocusCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("월간 몰입 캘린더")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("점은 세션에서 남긴 집중 체감이에요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            monthlyFocusLegend
            monthlyCalendarWeekdayHeader
            ForEach(
                Array(monthWeeks.enumerated()),
                id: \.offset
            ) { index, week in
                monthlyCalendarWeekRow(
                    week,
                    weekNumber: index + 1
                )
            }

            Text("날짜는 일간, 왼쪽 주차는 주간 몰입 기록으로 이동해요.")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .popoverCard(padding: 16)
    }

    private var monthlyFocusLegend: some View {
        HStack(spacing: 12) {
            ForEach(focusResponseBuckets) { bucket in
                HStack(spacing: 4) {
                    Circle()
                        .fill(bucket.color)
                        .frame(width: 7, height: 7)
                    Text(bucket.label)
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var monthlyCalendarWeekdayHeader: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: 42, height: 1)
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthlyCalendarWeekRow(
        _ week: [Date?],
        weekNumber: Int
    ) -> some View {
        HStack(spacing: 6) {
            if let weekDate = week.compactMap({ $0 }).first {
                Button {
                    onNavigate(.weekly, weekDate)
                } label: {
                    Text("\(weekNumber)주")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(width: 42, height: 76)
                        .background(
                            PopoverChrome.surface,
                            in: RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                            .stroke(PopoverChrome.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 42, height: 76)
            }

            ForEach(week.indices, id: \.self) { index in
                if let date = week[index] {
                    monthlyDayCell(date)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                }
            }
        }
    }

    private func monthlyDayCell(
        _ date: Date
    ) -> some View {
        let day = periodCalendar.startOfDay(for: date)
        let dayRows = filteredRowsByDay[day] ?? []
        let reflectedRows = dayRows.filter { focusLevel(for: $0) != nil }
        let completedCount = dayRows.filter {
            $0.progressResult == .completedAsPlanned
        }.count
        let remainingCount = dayRows.filter {
            $0.progressResult == .meaningfulProgress
                || $0.progressResult == .littleProgress
        }.count
        let changedCount = dayRows.filter {
            $0.progressResult == .goalChanged
        }.count
        return Button {
            onNavigate(.daily, date)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(dayNumberText(date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer(minLength: 2)
                    if !dayRows.isEmpty {
                        Text("\(dayRows.count)회")
                            .font(.caption2)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .monospacedDigit()
                    }
                }

                if dayRows.isEmpty {
                    Text("기록 없음")
                        .font(.system(size: 9))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 3) {
                        ForEach(
                            Array(reflectedRows.prefix(6)),
                            id: \.id
                        ) { row in
                            Circle()
                                .fill(focusTint(for: row))
                                .frame(width: 7, height: 7)
                        }
                        if reflectedRows.count > 6 {
                            Text("+\(reflectedRows.count - 6)")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        if completedCount > 0 {
                            Text("완료 \(completedCount)")
                                .foregroundStyle(Color.green)
                        }
                        if remainingCount > 0 {
                            Text("남음 \(remainingCount)")
                                .foregroundStyle(Color.blue)
                        }
                        if changedCount > 0 {
                            Text("변경 \(changedCount)")
                                .foregroundStyle(PopoverChrome.inkTertiary)
                        }
                    }
                    .font(.system(size: 8.5, weight: .semibold))
                    .monospacedDigit()
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 76)
            .background(
                dayRows.isEmpty
                    ? PopoverChrome.surface
                    : PopoverChrome.selectionFill.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PopoverChrome.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(monthlyDayHelp(date: date, rows: dayRows))
    }

    private var monthlyWeekdayPatternCard: some View {
        let maximum = max(
            1,
            focusResponseBuckets.flatMap { bucket in
                (0..<7).map {
                    weekdayResponseCount(
                        bucketID: bucket.id,
                        weekdayIndex: $0
                    )
                }
            }.max() ?? 1
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("요일별 반복 패턴")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("평균이 아니라 실제 회고 응답 횟수예요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            HStack(spacing: 6) {
                Color.clear
                    .frame(width: 86, height: 1)
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(focusResponseBuckets) { bucket in
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(bucket.color)
                            .frame(width: 7, height: 7)
                        Text(bucket.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }
                    .frame(width: 86, alignment: .leading)

                    ForEach(0..<7, id: \.self) { weekdayIndex in
                        let count = weekdayResponseCount(
                            bucketID: bucket.id,
                            weekdayIndex: weekdayIndex
                        )
                        Text(count == 0 ? "–" : "\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                count == 0
                                    ? PopoverChrome.inkTertiary
                                    : PopoverChrome.ink
                            )
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                bucket.color.opacity(
                                    count == 0
                                        ? 0.03
                                        : 0.08
                                            + 0.22
                                            * Double(count)
                                            / Double(maximum)
                                ),
                                in: RoundedRectangle(
                                    cornerRadius: 6,
                                    style: .continuous
                                )
                            )
                    }
                }
            }

            if missingReflectionCount > 0 {
                Text("회고가 없는 세션: \(missingReflectionCount)회")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
        .popoverCard(padding: 16)
    }

    private var weekdaySymbols: [String] {
        ["월", "화", "수", "목", "금", "토", "일"]
    }

    private func weekdayResponseCount(
        bucketID: Int,
        weekdayIndex: Int
    ) -> Int {
        filteredRows.filter { row in
            guard focusLevel(for: row) == bucketID else { return false }
            return FocusPeriodCalendarBuilder.mondayIndex(
                for: row.startedAt,
                calendar: periodCalendar
            ) == weekdayIndex
        }.count
    }

    private func monthlyDayHelp(
        date: Date,
        rows: [FocusSessionRow]
    ) -> String {
        guard !rows.isEmpty else {
            return "\(fullDateText(date)) · 기록 없음 · 눌러서 일간 보기"
        }
        let responses = focusResponseBuckets.compactMap { bucket -> String? in
            let count = rows.filter { focusLevel(for: $0) == bucket.id }.count
            return count > 0 ? "\(bucket.label) \(count)회" : nil
        }
        return "\(fullDateText(date)) · \(rows.count)회 · \(responses.joined(separator: " · "))"
    }

    private func focusLevel(
        for row: FocusSessionRow
    ) -> Int? {
        if let rating = row.rating {
            return rating
        }
        if row.selfAssessmentLabel == PomodoroFocusExperience.unsure.label {
            return 0
        }
        return nil
    }

    private func focusTint(
        for row: FocusSessionRow
    ) -> Color {
        guard let level = focusLevel(for: row) else {
            return PopoverChrome.divider
        }
        return focusResponseBuckets.first { $0.id == level }?.color
            ?? PopoverChrome.inkTertiary
    }

    private func progressTint(
        _ progressResult: PomodoroProgressResult?
    ) -> Color {
        switch progressResult {
        case .completedAsPlanned: return .green
        case .meaningfulProgress: return .blue
        case .littleProgress: return .red
        case .goalChanged, .none: return PopoverChrome.inkTertiary
        }
    }

    private func focusLevelLabel(
        _ level: Int
    ) -> String {
        focusResponseBuckets.first { $0.id == level }?.label ?? ""
    }

    private func weekdayDayText(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E d"
        return formatter.string(from: date)
    }

    private func dayNumberText(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func fullDateText(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: date)
    }

    // MARK: 몰입 지도

    private var focusMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("몰입 패턴 차트")
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
                Text("이 기간에는 ‘키보드·마우스 사용률’을 기록한 세션이 아직 없어요.")
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
            Text("‘잘 모르겠어요’는 몰입 점수가 없어 차트에서 빼요.")
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
        .help(metric.isAvailable ? "가로축을 이 지표로 바꿉니다" : "아직 사용할 수 없는 지표입니다")
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
        let longestDuration = formattedMetricDuration(
            Double(row.observation.longestContinuousAppUsage?.durationSeconds ?? 0)
        )
        var parts: [String] = [timeRangeText(row)]
        if let label = row.selfAssessmentLabel {
            parts.append("자기평가: \(label)")
        }
        parts.append(completionDetailText(row))
        parts.append("한 곳 최장 사용: \(longestDuration)")
        if row.observation.appSwitchCount > 0,
           let interval = row.averageAppSwitchIntervalSeconds {
            parts.append("평균 전환 간격: \(formattedMetricDuration(interval))")
        }
        parts.append("앱·웹 사용 비중: \(Int((row.appUsageRatio * 100).rounded()))%")
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

    private var taskGroupListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(taskGroupSectionTitle)
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                sessionMetricInfoButton
                Spacer()
                Text(taskGroupSectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            ForEach(taskGroups) { group in
                taskGroupCard(group)
            }
        }
    }

    private var taskGroupSectionTitle: String {
        switch viewMode {
        case .daily: return "할 일별 세션"
        case .weekly: return "이번 주 할 일별 세션"
        case .monthly: return "이번 달 할 일별 세션"
        }
    }

    private var taskGroupSectionSubtitle: String {
        switch viewMode {
        case .daily:
            return "같은 할 일의 세션을 묶어서 표시 · \(filteredRows.count)개 세션"
        case .weekly:
            return "펼치면 회차별 집중·진척 흐름을 확인 · \(filteredRows.count)개 세션"
        case .monthly:
            return "여러 날 이어진 회차 흐름을 확인 · \(filteredRows.count)개 세션"
        }
    }

    private func taskGroupCard(_ group: FocusTaskSessionGroup) -> some View {
        let isExpanded = expandedTaskGroupIDs.contains(group.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if isExpanded {
                    expandedTaskGroupIDs.remove(group.id)
                } else {
                    expandedTaskGroupIDs.insert(group.id)
                }
            } label: {
                HStack(spacing: 8) {
                    taskGroupCategoryIndicator(group)
                    Text(group.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(1)
                    if group.linkedMemoID == nil {
                        taskGroupBadge("미연결", tint: PopoverChrome.inkTertiary)
                    }
                    if group.completedInPeriod {
                        taskGroupBadge("이 기간에 완료", tint: PopoverChrome.accent)
                    }
                    if group.pendingReflectionCount > 0 {
                        taskGroupBadge(
                            "회고 대기 \(group.pendingReflectionCount)회",
                            tint: .orange
                        )
                    }
                    Spacer(minLength: 8)
                    Text("\(group.rows.count)개 세션")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .monospacedDigit()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(taskGroupMetricItems(group).enumerated()), id: \.offset) { _, item in
                        metricLabel(item.text, muted: item.muted, help: item.help)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(taskGroupMetricItems(group).enumerated()), id: \.offset) { _, item in
                        metricLabel(item.text, muted: item.muted, help: item.help)
                    }
                }
            }

            Text(taskGroupAssessmentText(group))
                .font(.caption)
                .foregroundStyle(
                    group.assessmentCounts.isEmpty
                        ? PopoverChrome.inkTertiary
                        : PopoverChrome.inkSecondary
                )
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                Divider()
                if group.rows.count > 1 {
                    FocusTaskSessionTrendView(
                        points: FocusTaskSessionTrendBuilder.points(
                            rows: group.rows,
                            completedSessionIDs: completedTaskSessionIDs
                        ),
                        selectedSessionID: $selectedSessionID,
                        hoveredSessionID: $hoveredTaskSessionID
                    )
                    Divider()
                }
                ForEach(group.rows) { row in
                    sessionCard(row)
                }
            }
        }
        .padding(12)
        .background(
            PopoverChrome.surface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.divider, lineWidth: 1)
        )
    }

    private func taskGroupCategoryIndicator(
        _ group: FocusTaskSessionGroup
    ) -> some View {
        HStack(spacing: -3) {
            ForEach(Array(group.categories.prefix(3)), id: \.self) { category in
                Circle()
                    .fill(Constants.categoryColor(for: category))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(PopoverChrome.surface, lineWidth: 1))
            }
        }
        .help(
            group.categories.count == 1
                ? (group.categories.first ?? "")
                : group.categories.joined(separator: ", ")
        )
    }

    private func taskGroupBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private func taskGroupMetricItems(
        _ group: FocusTaskSessionGroup
    ) -> [SessionMetricItem] {
        var items: [SessionMetricItem] = [
            (
                text: "세션 수: \(group.rows.count)회",
                muted: false,
                help: nil
            ),
            (
                text: "실제 진행 시간: \(formattedMetricDuration(Double(group.totalDurationSeconds)))",
                muted: false,
                help: nil
            ),
            (
                text: "예정된 종료: \(group.completedAsPlannedCount)회",
                muted: false,
                help: nil
            ),
            (
                text: "조기 종료: \(group.endedEarlyCount)회",
                muted: false,
                help: nil
            ),
        ]
        if group.unknownEndCount > 0 {
            items.append((
                text: "(종료 방식 미기록: \(group.unknownEndCount)회)",
                muted: true,
                help: nil
            ))
        }
        return items
    }

    private func taskGroupAssessmentText(
        _ group: FocusTaskSessionGroup
    ) -> String {
        guard !group.assessmentCounts.isEmpty else {
            return "자기평가: 없음"
        }
        let summary = group.assessmentCounts
            .map { "\($0.label) \($0.count)회" }
            .joined(separator: " · ")
        return "자기평가: \(summary)"
    }

    private var sessionMetricInfoButton: some View {
        Button {
            showsSessionMetricInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .buttonStyle(.plain)
        .help("세션별 지표의 의미와 계산 방법")
        .popover(isPresented: $showsSessionMetricInfo) {
            sessionMetricInfoPopover
        }
        .accessibilityLabel("세션별 지표 설명")
    }

    private var sessionMetricInfoPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("세션별 지표 안내")
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text("각 수치가 무엇을 보여 주고 어떻게 계산되는지 설명합니다.")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }

                metricExplanation(
                    title: "실제 진행 시간",
                    meaning: "이 포모도로에서 카운트다운이 실제로 진행된 시간입니다. 일시정지 시간은 제외하고, 조기 종료했다면 종료 시점까지만 계산해요.",
                    formula: "카운트다운이 실제로 줄어든 시간"
                )
                metricExplanation(
                    title: "진행 상태",
                    meaning: "‘예정된 종료’는 설정한 시간이 만료된 세션이고, ‘조기 종료’는 시간이 남았을 때 기록 후 종료한 세션입니다. 과거 기록처럼 구분할 수 없으면 ‘종료 방식 미기록’으로 표시해요.",
                    formula: "타이머 만료 또는 기록 후 종료 여부"
                )
                metricExplanation(
                    title: "한 곳 최장 사용",
                    meaning: "한 앱이나 웹사이트를 끊김 없이 사용한 구간 중 가장 긴 시간입니다.",
                    formula: "가장 긴 연속 앱·웹 사용 구간"
                )
                metricExplanation(
                    title: "평균 전환 간격",
                    meaning: "전환이 있었던 세션에서 앱이나 웹사이트를 바꾸기 전까지 평균적으로 유지한 시간입니다. 전환이 없으면 표시하지 않아요.",
                    formula: "명확히 기록된 사용 시간 ÷ (전환 횟수 + 1)"
                )
                metricExplanation(
                    title: "사용한 앱·웹 수",
                    meaning: "세션 중 사용한 서로 다른 앱과 구분 가능한 웹사이트의 수입니다. 짧은 생산성 앱 사용은 제외해요.",
                    formula: "전환 계산에 반영된 앱·웹의 고유 개수"
                )
                metricExplanation(
                    title: "전환 횟수",
                    meaning: "기록 순서에서 사용한 앱이나 웹사이트가 달라진 횟수입니다. A → B → A라면 2회로 셉니다. 짧은 생산성 앱 사용은 앞뒤 흐름을 잇고 별도로 표시해요.",
                    formula: "앱·웹 사용 순서에서 앞뒤 대상이 달라진 횟수"
                )
                metricExplanation(
                    title: "짧은 생산성 앱 사용",
                    meaning: "생산성 관리 카테고리의 앱을 10초 미만으로 사용한 횟수입니다. 짧은 확인이나 타이머 조작이 사용 흐름을 왜곡하지 않도록 앱·웹 사용 수와 전환 횟수에서는 제외해요.",
                    formula: "10초 미만으로 이어진 생산성 관리 앱 사용 구간 수"
                )
                metricExplanation(
                    title: "앱·웹 사용 비중",
                    meaning: "세션 동안 앱·웹 사용 기록이 얼마나 이어졌는지 보여 줍니다. 값이 낮으면 자리 비움뿐 아니라 추적 중단이나 기록 누락도 확인해야 해요.",
                    formula: "앱·웹 사용 기록 시간 ÷ 실제 진행 시간 × 100"
                )
                metricExplanation(
                    title: "키보드·마우스 사용률",
                    meaning: "실제 진행 시간 중 키보드나 마우스 입력이 이어진 비율입니다. 생각하거나 읽는 시간이 많은 작업은 집중했어도 낮게 나올 수 있어요.",
                    formula: "최근 2초 안에 입력이 있었던 초 ÷ 실제 진행 시간 × 100"
                )

                Divider()

                Text("‘앱·웹 기록: 없음’은 해당 세션에 사용 기록이 없다는 뜻이고, ‘—’는 이 지표를 수집하기 전에 생성된 세션이라는 뜻입니다. 미분류 기록도 관련 지표에는 포함됩니다.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(width: 420, height: 580)
    }

    private func metricExplanation(
        title: String,
        meaning: String,
        formula: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text(meaning)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("계산 · \(formula)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(PopoverChrome.accent)
                .fixedSize(horizontal: false, vertical: true)
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
        .help("이 세션의 몰입 패턴 차트 점 색을 바꿉니다")
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
            Button {
                setMarkerColor(nil, for: row)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Constants.categoryColor(for: row.category))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(PopoverChrome.divider, lineWidth: 1))
                    Text("\(row.category) 기본색 사용")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PopoverChrome.ink)
                        .opacity(row.markerColorKey == nil ? 1 : 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    row.markerColorKey == nil ? PopoverChrome.selectionFill : PopoverChrome.card,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(PopoverChrome.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("이 세션의 개별 색상을 지우고 카테고리 기본색을 사용합니다")
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(FocusMarkerPalette.colors) { item in
                    swatch(
                        color: item.color,
                        selected: row.markerColorKey == item.key,
                        name: item.name
                    ) { setMarkerColor(item.key, for: row) }
                }
            }
            Text("아래 색상은 이 세션에만 적용됩니다.")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .padding(14)
        .frame(width: 208)
    }

    private func swatch(
        color: Color,
        selected: Bool,
        name: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle().strokeBorder(
                        PopoverChrome.inkSecondary,
                        lineWidth: 1.5
                    )
                    .opacity(0.15)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(selected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(name)
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
        let isPersistentlySelected = selectedSessionID == row.id
        let isSelected = isPersistentlySelected || hoveredTaskSessionID == row.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                colorSwatchButton(for: row)
                Text("\(row.emoji) \(row.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                completionBadge(row)
                Spacer(minLength: 8)
                if let selfAssessmentLabel = row.selfAssessmentLabel {
                    Text(selfAssessmentLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PopoverChrome.accent)
                        .lineLimit(1)
                } else {
                    if row.isReflectionPending {
                        taskGroupBadge("회고 대기", tint: .orange)
                    }
                    Button("회고 작성") {
                        showReflection(for: row)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("이 포모도로의 회고를 지금 작성합니다")
                }
                Text(timeRangeText(row))
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }

            ViewThatFits(in: .horizontal) {
                sessionMetricGroups(row)
                sessionMetricGroups(row, stacked: true)
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
            selectedSessionID = isPersistentlySelected ? nil : row.id
        }
    }

    private func showReflection(for row: FocusSessionRow) {
        PomodoroReflectionPanel.shared.show(
            focusSessionID: row.id,
            modelContext: modelContext
        )
    }

    @ViewBuilder
    private func sessionMetricGroups(
        _ row: FocusSessionRow,
        stacked: Bool = false
    ) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                sessionMetricGroup(title: "시간 지표", items: timeMetricItems(row))
                Divider()
                sessionMetricGroup(title: "앱·웹 사용", items: appWebMetricItems(row))
                Divider()
                sessionMetricGroup(title: "활동 비중", items: activityMetricItems(row))
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                sessionMetricGroup(title: "시간 지표", items: timeMetricItems(row))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                sessionMetricGroup(title: "앱·웹 사용", items: appWebMetricItems(row))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                sessionMetricGroup(title: "활동 비중", items: activityMetricItems(row))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sessionMetricGroup(
        title: String,
        items: [SessionMetricItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PopoverChrome.inkTertiary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        metricLabel(item.text, muted: item.muted, help: item.help)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        metricLabel(item.text, muted: item.muted, help: item.help)
                    }
                }
            }
        }
    }

    private typealias SessionMetricItem = (text: String, muted: Bool, help: String?)

    private func timeMetricItems(
        _ row: FocusSessionRow
    ) -> [SessionMetricItem] {
        var sessionDurationText = "실제 진행 시간: \(formattedMetricDuration(Double(row.durationSeconds)))"
        if row.completionStatus == .endedEarly,
           let plannedDurationSeconds = row.plannedDurationSeconds,
           plannedDurationSeconds > row.durationSeconds {
            sessionDurationText += " (설정 \(formattedMetricDuration(Double(plannedDurationSeconds))))"
        }
        var items: [SessionMetricItem] = [
            (
                text: sessionDurationText,
                muted: false,
                help: nil
            )
        ]
        if let longest = row.observation.longestContinuousAppUsage,
           longest.durationSeconds > 0 {
            items.append((
                text: "한 곳 최장 사용: \(formattedMetricDuration(Double(longest.durationSeconds)))",
                muted: false,
                help: nil
            ))
        }
        if row.observation.appSwitchCount > 0,
           let interval = row.averageAppSwitchIntervalSeconds {
            items.append((
                text: "평균 전환 간격: \(formattedMetricDuration(interval))",
                muted: false,
                help: nil
            ))
        }
        return items
    }

    private func appWebMetricItems(
        _ row: FocusSessionRow
    ) -> [SessionMetricItem] {
        guard row.observation.hasRecords else {
            return [(text: "앱·웹 기록: 없음", muted: true, help: nil)]
        }

        var items: [SessionMetricItem] = [
            (text: "사용한 앱·웹 수: \(row.appCount)개", muted: false, help: nil),
            (
                text: row.observation.appSwitchCount == 0
                    ? "전환 횟수: 없음"
                    : "전환 횟수: \(row.observation.appSwitchCount)회",
                muted: false,
                help: nil
            ),
        ]
        if row.observation.shortProductivityManagementVisitCount > 0 {
            items.append((
                text: "(짧은 생산성 앱 사용: \(row.observation.shortProductivityManagementVisitCount)회)",
                muted: true,
                help: "생산성 관리 카테고리의 앱을 10초 미만으로 사용한 횟수예요. 앱·웹 사용 수와 전환 횟수에서는 제외합니다."
            ))
        }
        if row.unclassifiedAppCount > 0 {
            items.append((
                text: "미분류: \(row.unclassifiedAppCount)개",
                muted: true,
                help: nil
            ))
        }
        return items
    }

    private func activityMetricItems(
        _ row: FocusSessionRow
    ) -> [SessionMetricItem] {
        var items: [SessionMetricItem] = [
            (
                text: "앱·웹 사용 비중: \(Int((row.appUsageRatio * 100).rounded()))%",
                muted: !row.observation.hasRecords,
                help: nil
            )
        ]
        if let pct = row.inputActivityPercent {
            items.append((
                text: "키보드·마우스 사용률: \(pct)%",
                muted: false,
                help: nil
            ))
        } else {
            items.append((
                text: "키보드·마우스 사용률: —",
                muted: true,
                help: nil
            ))
        }
        return items
    }

    @ViewBuilder
    private func metricLabel(_ text: String, muted: Bool, help: String?) -> some View {
        let label = Text(text)
            .font(.caption)
            .foregroundStyle(muted ? PopoverChrome.inkTertiary : PopoverChrome.inkSecondary)
            .monospacedDigit()
            .lineLimit(1)
        if let help {
            label.help(help)
        } else {
            label
        }
    }

    private func formattedMetricDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        guard totalSeconds >= 60 else { return "\(totalSeconds)초" }
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        guard remainingSeconds > 0 else { return "\(minutes)분" }
        return "\(minutes)분 \(remainingSeconds)초"
    }

    private func timeRangeText(_ row: FocusSessionRow) -> String {
        let timeRange = "\(focusTimeFormatter.string(from: row.startedAt))–\(focusTimeFormatter.string(from: row.endedAt))"
        guard viewMode != .daily else { return timeRange }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d(E)"
        return "\(formatter.string(from: row.startedAt)) \(timeRange)"
    }

    private func completionDetailText(_ row: FocusSessionRow) -> String {
        guard row.completionStatus == .endedEarly,
              let plannedDurationSeconds = row.plannedDurationSeconds,
              plannedDurationSeconds > row.durationSeconds else {
            return row.completionStatus.label
        }
        return "\(row.completionStatus.label) (설정 \(formattedMetricDuration(Double(plannedDurationSeconds))))"
    }

    private func completionBadge(_ row: FocusSessionRow) -> some View {
        let tint: Color = switch row.completionStatus {
        case .completedAsPlanned: PopoverChrome.accent
        case .endedEarly: .orange
        case .unknown: PopoverChrome.inkTertiary
        }
        return Text(row.completionStatus.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .help(row.completionStatus.help)
    }
}
