import SwiftUI
import SwiftData
import OSLog

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
    let timerSessions: [FocusSession]
    let aggregateSnapshot: StatsAggregateSnapshot?
}

struct StatsDetailWindow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: StatsViewMode = .daily
    @State private var selectedDate: Date = Date()
    @State private var records: [AppUsageRecord] = []
    @State private var dailySegments: [AppUsageSegment] = []
    @State private var weekSegments: [AppUsageSegment] = []
    @State private var periodSegments: [AppUsageSegment] = []
    @State private var timerSessions: [FocusSession] = []
    @State private var aggregateSnapshot: StatsAggregateSnapshot?
    @State private var showEditor: Bool = false
    @State private var trackerStore = TrackerStateStore.shared
    @State private var loadCache: [StatsLoadCacheKey: StatsLoadedData] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.horonghorong",
        category: "StatsDetail"
    )

    init(initialViewMode: StatsViewMode = .daily) {
        _viewMode = State(initialValue: initialViewMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if shouldShowVacationIllustration {
                // 일러스트 자체가 휴가 컨텍스트를 충분히 전달하므로 상단 배너는 생략.
                vacationIllustration
            } else {
                vacationBanner
                ScrollView {
                    StatsChartView(
                        records: records,
                        viewMode: viewMode,
                        referenceDate: selectedDate,
                        dailySegments: dailySegments,
                        weekSegments: weekSegments,
                        periodSegments: periodSegments,
                        timerSessions: timerSessions,
                        aggregateSnapshot: aggregateSnapshot,
                        vacationDays: viewMode == .monthly ? vacationDaysInMonth : []
                    )
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(PopoverChrome.surface)
        .onAppear {
            logViewTrigger("appear")
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
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
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

            Picker("기간", selection: $viewMode) {
                ForEach(StatsViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            dateNavigator

            Button {
                showEditor = true
            } label: {
                Label("편집", systemImage: "pencil")
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .disabled(viewMode != .daily)
            .help(viewMode == .daily ? "이 날짜의 세그먼트를 수동 편집" : "일간 뷰에서만 사용할 수 있습니다")
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
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
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

        let loadedData = StatsLoadedData(
            records: fetchedRecords,
            dailySegments: loadedSegments.daily,
            weekSegments: loadedSegments.week,
            periodSegments: loadedSegments.period,
            timerSessions: fetchedSessions,
            aggregateSnapshot: aggregate
        )
        loadCache[key] = loadedData
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
        timerSessions = data.timerSessions
        aggregateSnapshot = data.aggregateSnapshot
        Self.logger.notice("StatsDetail view update apply mode=\(viewMode.rawValue, privacy: .public) records=\(data.records.count) dailySegments=\(data.dailySegments.count) weekSegments=\(data.weekSegments.count) periodSegments=\(data.periodSegments.count) sessions=\(data.timerSessions.count) aggregate=\(data.aggregateSnapshot == nil ? "none" : "ready", privacy: .public)")
    }

    private func invalidateLoadCache() {
        loadCache.removeAll()
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

    private func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
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
            guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else {
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
