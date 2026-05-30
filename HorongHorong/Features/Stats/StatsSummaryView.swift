import AppKit
import SwiftUI
import SwiftData

struct CategoryUsage: Identifiable {
    let id = UUID()
    let category: String
    let emoji: String
    let color: Color
    let durationSeconds: Int

    var hours: Double {
        Double(durationSeconds) / 3600.0
    }

    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        return "\(h)h \(m)m"
    }
}

private struct SummaryPomodoroFocusWindow {
    let start: Date
    let end: Date
    let category: String
}

private enum StatsSummaryScope: String, CaseIterable, Identifiable {
    case today = "오늘"
    case week = "이번 주"

    var id: String { rawValue }
}

struct StatsSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var categoryUsages: [CategoryUsage] = []
    @State private var weeklyDailyTotals: [(date: Date, durationSeconds: Int)] = []
    @State private var todayFocusSummary = DailyFocusSummary(
        totalSeconds: 0,
        switches: 0,
        longestFocusSeconds: 0,
        topCategory: nil,
        overallScore: 0
    )
    @State private var todayAttentionSummary = AttentionSummary.empty
    @State private var weekLongestSessionSeconds: Int = 0
    @State private var hoveredScope: StatsSummaryScope?
    @State private var scope: StatsSummaryScope = .today
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(spacing: 12) {
            scopePicker
            ScrollView {
                Group {
                    if scope == .today, categoryUsages.isEmpty {
                        emptyState
                    } else if scope == .week, weeklyDailyTotals.allSatisfy({ $0.durationSeconds == 0 }) {
                        emptyState
                    } else {
                        if scope == .today {
                            todaySummary
                        } else {
                            weekSummary
                        }
                    }
                }
                .padding(.trailing, 12)
            }
        }
        .onAppear { loadData() }
        .onChange(of: scope) { _, _ in loadData() }
        .configureHostWindow { window in
            hostWindow = window
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(StatsSummaryScope.allCases) { item in
                Button {
                    scope = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: scope == item ? .bold : .medium, design: .rounded))
                        .foregroundStyle(scope == item ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(scopeChipFill(for: item))
                        )
                        .shadow(color: scope == item ? PopoverChrome.accent.opacity(0.28) : .clear, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredScope = isHovering ? item : nil
                }
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func scopeChipFill(for item: StatsSummaryScope) -> Color {
        if scope == item {
            return PopoverChrome.accent
        }
        if hoveredScope == item {
            return PopoverChrome.card
        }
        return .clear
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("아직 기록된 데이터가 없습니다")
                .font(.subheadline)
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .popoverCard()
    }

    private var todaySummary: some View {
        VStack(spacing: 10) {
            summaryHeader(title: "오늘 집중", total: "총 \(shortDuration(totalUsageSeconds))", showsTop3: true)

            if !categoryUsages.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    summaryDonut
                        .frame(width: 88, height: 88)
                    VStack(spacing: 6) {
                        ForEach(topCategoryUsages) { usage in
                            compactUsageRow(usage)
                        }
                    }
                }
                .popoverCard()
            }

            metricCards
            horongStatusCard
        }
    }

    private func summaryHeader(title: String, total: String, showsTop3: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PopoverChrome.accent)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                if showsTop3 {
                    Text("TOP 3")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            Spacer()
            detailButton
        }
        .overlay(alignment: .bottomLeading) {
            Text(total)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .offset(y: 20)
        }
        .padding(.bottom, 22)
    }

    private var summaryDonut: some View {
        let total = max(1, topCategoryUsages.reduce(0) { $0 + $1.durationSeconds })
        return ZStack {
            Circle()
                .stroke(PopoverChrome.surfaceAlt, lineWidth: 14)
            ForEach(Array(topCategoryUsages.enumerated()), id: \.element.id) { index, usage in
                Circle()
                    .trim(from: trimStart(for: index, total: total), to: trimEnd(for: index, total: total))
                    .stroke(usage.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(shortDuration(total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
            }
        }
    }

    private func trimStart(for index: Int, total: Int) -> CGFloat {
        let prior = topCategoryUsages.prefix(index).reduce(0) { $0 + $1.durationSeconds }
        return CGFloat(prior) / CGFloat(total)
    }

    private func trimEnd(for index: Int, total: Int) -> CGFloat {
        let through = topCategoryUsages.prefix(index + 1).reduce(0) { $0 + $1.durationSeconds }
        return CGFloat(through) / CGFloat(total)
    }

    private func compactUsageRow(_ usage: CategoryUsage) -> some View {
        let total = max(1, totalUsageSeconds)
        let percent = Int(round(Double(usage.durationSeconds) / Double(total) * 100))
        return HStack(spacing: 6) {
            Circle()
                .fill(usage.color)
                .frame(width: 8, height: 8)
            Text(usage.emoji)
            Text(usage.category)
                .font(.caption)
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer()
            Text(shortDuration(usage.durationSeconds))
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
            Text("\(percent)%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.inkTertiary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var metricCards: some View {
        HStack(spacing: 8) {
            summaryMetricCard(label: "최장 세션", value: shortDuration(todayFocusSummary.longestFocusSeconds))
            summaryMetricCard(label: "작업 전환", value: "\(todayFocusSummary.switches)회")
        }
    }

    private func summaryMetricCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverCard(padding: 12, radius: 10)
    }

    private var horongStatusCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("FocusOnTransparent")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(3)
                .frame(width: 30, height: 30)
                .background(PopoverChrome.card, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("오늘 호롱이 상태")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("— \(horongStatusLabel) \(horongStatusEmoji)")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Text(horongStatusMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)

                if todayAttentionSummary.hasSignals {
                    VStack(spacing: 5) {
                        ForEach(attentionEvidenceEvents) { event in
                            attentionEvidenceRow(event)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var usageBars: some View {
        VStack(spacing: 6) {
            ForEach(categoryUsages) { usage in
                HStack(spacing: 8) {
                    Text(usage.emoji)
                        .frame(width: 20)
                    Text(usage.category)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.ink)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(usage.color.opacity(0.78))
                            .frame(width: barWidth(for: usage, in: geo.size.width))
                    }
                    .frame(height: 12)

                    Text(usage.formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .popoverCard()
    }

    private var weekSummary: some View {
        VStack(spacing: 10) {
            summaryHeader(title: "이번 주 집중", total: "총 \(weekTotalFormatted)", showsTop3: false)

            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weeklyDailyTotals, id: \.date) { day in
                        weekBar(day)
                    }
                }
                .frame(height: 118, alignment: .bottom)
            }
            .overlay(alignment: .topTrailing) {
                Text(weekChartMaxLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
            }
            .popoverCard()

            weekMetricCards
            weekStatusCard
        }
    }

    private var attentionEvidenceEvents: [AttentionEventCandidate] {
        Array(todayAttentionSummary.events.filter { $0.type != .allowedSwitch }.prefix(3))
    }

    private func attentionEvidenceRow(_ event: AttentionEventCandidate) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attentionIcon(for: event.type))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 14)
            Text(event.reason)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button {
                    saveAttentionCorrection(for: event, verdict: .distraction)
                } label: {
                    Label("신호 맞음", systemImage: "checkmark.seal")
                }
                Button {
                    saveAttentionCorrection(for: event, verdict: .notDistraction)
                } label: {
                    Label("방해 아님", systemImage: "checkmark.circle")
                }
                Button {
                    saveAttentionCorrection(for: event, verdict: .misclassified)
                } label: {
                    Label("분류 오류", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("이 근거 보정")
        }
    }

    private func attentionIcon(for type: AttentionEventType) -> String {
        switch type {
        case .selectiveDistraction: return "bell.badge"
        case .sustainedDrop: return "timer"
        case .delayedReturn: return "arrow.uturn.backward.circle"
        case .allowedSwitch: return "checkmark.circle"
        }
    }

    private func weekBar(_ day: (date: Date, durationSeconds: Int)) -> some View {
        let maxDuration = max(weekChartMaxDuration, 1)
        let height = day.durationSeconds > 0 ? max(8, CGFloat(day.durationSeconds) / CGFloat(maxDuration) * 78) : 8
        let isToday = Calendar.current.isDateInToday(day.date)
        let isFuture = day.date > Calendar.current.startOfDay(for: Date())
        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                if isToday {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(PopoverChrome.accentSoft, lineWidth: 2)
                        .frame(width: 40, height: height + 8)
                }

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(weekBarFill(duration: day.durationSeconds, isToday: isToday, isFuture: isFuture))
                    .frame(width: 32, height: height)
                    .padding(.bottom, isToday ? 4 : 0)
            }
            .frame(height: 94, alignment: .bottom)

            Text(weekdayLabel(day.date))
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? PopoverChrome.accent : PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekChartMaxDuration: Int {
        weeklyDailyTotals.map(\.durationSeconds).max() ?? 0
    }

    private var weekChartMaxLabel: String {
        shortDuration(weekChartMaxDuration)
    }

    private func weekBarFill(duration: Int, isToday: Bool, isFuture: Bool) -> Color {
        if duration == 0 || isFuture {
            return PopoverChrome.surfaceAlt
        }
        return isToday ? PopoverChrome.accent : PopoverChrome.accent.opacity(0.9)
    }

    private var weekMetricCards: some View {
        HStack(spacing: 8) {
            summaryMetricCard(label: "오늘 누적", value: formatMetricDuration(todayWeeklySeconds))
            summaryMetricCard(label: "최장 세션", value: formatMetricDuration(weekLongestSessionSeconds))
        }
    }

    private var weekStatusCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("FocusOnTransparent")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(3)
                .frame(width: 30, height: 30)
                .background(PopoverChrome.card, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(weeklyActiveStreak)일 연속")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("호롱불을 켰어요 🔥")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Text("오늘도 작은 호롱이가 함께 있을게요.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailButton: some View {
        Button {
            let popoverWindow = hostWindow
            openWindow(id: "stats-detail")
            popoverWindow?.orderOut(nil)
            // MenuBarExtra 앱은 accessory 정책이라 openWindow만으로는 앞으로 오지 않음.
            // 창이 생성/재사용된 뒤 활성화 + orderFrontRegardless 로 최상단으로 끌어올린다.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == "stats-detail" || $0.title == "호롱호롱 통계"
                }) {
                    window.collectionBehavior.insert(.moveToActiveSpace)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text("상세 보기")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    private var topCategoryUsages: [CategoryUsage] {
        Array(categoryUsages.prefix(3))
    }

    private var totalUsageSeconds: Int {
        categoryUsages.reduce(0) { $0 + $1.durationSeconds }
    }

    private var todayWeeklySeconds: Int {
        weeklyDailyTotals.first { Calendar.current.isDateInToday($0.date) }?.durationSeconds ?? 0
    }

    private var weeklyActiveStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalsByDay = Dictionary(uniqueKeysWithValues: weeklyDailyTotals.map {
            (calendar.startOfDay(for: $0.date), $0.durationSeconds)
        })

        var streak = 0
        var cursor = today
        while let duration = totalsByDay[cursor], duration > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private var horongStatusMessage: String {
        if todayAttentionSummary.hasSignals {
            return attentionStatusExplanation
        }

        switch todayFocusSummary.level {
        case .focused:
            return "큰 흔들림 없이 한 가지 흐름에 오래 머문 기록이에요."
        case .moderate:
            return "흐름은 이어졌지만 중간 전환이 조금 있었어요."
        case .scattered:
            return "전환이 여러 번 겹쳐 원래 흐름으로 돌아볼 신호가 있어요."
        case .empty:
            return "아직 기록이 없어요. 첫 집중을 시작해보세요."
        }
    }

    private var attentionStatusExplanation: String {
        let signalEvents = todayAttentionSummary.events.filter { $0.type != .allowedSwitch }
        let selectiveCount = signalEvents.filter { $0.type == .selectiveDistraction }.count
        let sustainedCount = signalEvents.filter { $0.type == .sustainedDrop }.count
        let returnCount = signalEvents.filter { $0.type == .delayedReturn }.count
        var parts: [String] = []

        if selectiveCount > 0 {
            parts.append("방해 앱 체류 \(selectiveCount)회")
        }
        if sustainedCount > 0 {
            parts.append("조기 중단 \(sustainedCount)회")
        }
        if returnCount > 0 {
            parts.append("복귀 지연 \(returnCount)회")
        }

        let summary = parts.isEmpty ? todayAttentionSummary.primaryMessage : "\(parts.joined(separator: ", "))가 보여요."
        guard let event = todayAttentionSummary.primaryEvent else {
            return summary
        }
        return "\(summary) 주요 근거: \(event.reason)."
    }

    private var horongStatusLabel: String {
        todayAttentionSummary.hasSignals ? todayAttentionSummary.levelLabel : todayFocusSummary.levelLabel
    }

    private var horongStatusEmoji: String {
        todayAttentionSummary.hasSignals ? todayAttentionSummary.levelEmoji : todayFocusSummary.levelEmoji
    }

    private func loadAttentionCorrections(from start: Date, to end: Date) -> [AttentionEventCorrection] {
        let descriptor = FetchDescriptor<AttentionEvent>(
            predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end }
        )
        let events = (try? modelContext.fetch(descriptor)) ?? []
        return events.map {
            AttentionEventCorrection(fingerprint: $0.fingerprint, verdict: $0.verdict)
        }
    }

    private func loadBreakTransitionIntents(from start: Date, to end: Date) -> [BreakTransitionIntent] {
        let descriptor = FetchDescriptor<BreakTransitionIntent>(
            predicate: #Predicate { $0.breakEndedAt >= start && $0.breakEndedAt < end },
            sortBy: [SortDescriptor(\.breakEndedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveAttentionCorrection(for event: AttentionEventCandidate, verdict: AttentionEventVerdict) {
        let fingerprint = event.fingerprint
        let descriptor = FetchDescriptor<AttentionEvent>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.eventType = event.type.rawValue
            existing.occurredAt = event.occurredAt
            existing.sourceApp = event.sourceApp
            existing.sourceCategory = event.sourceCategory
            existing.targetCategory = event.targetCategory
            existing.durationSeconds = event.durationSeconds
            existing.verdict = verdict
        } else {
            let correction = AttentionEvent(
                fingerprint: event.fingerprint,
                eventType: event.type.rawValue,
                occurredAt: event.occurredAt,
                sourceApp: event.sourceApp,
                sourceCategory: event.sourceCategory,
                targetCategory: event.targetCategory,
                durationSeconds: event.durationSeconds,
                verdict: verdict
            )
            modelContext.insert(correction)
        }

        try? modelContext.save()
        loadData()
    }

    private var totalFormatted: String {
        let total = categoryUsages.reduce(0) { $0 + $1.durationSeconds }
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)시간 \(m)분"
    }

    private var weekTotalFormatted: String {
        formatKoreanDuration(weeklyDailyTotals.reduce(0) { $0 + $1.durationSeconds })
    }

    private func barWidth(for usage: CategoryUsage, in maxWidth: CGFloat) -> CGFloat {
        let maxDuration = categoryUsages.map(\.durationSeconds).max() ?? 1
        guard maxDuration > 0 else { return 0 }
        return maxWidth * CGFloat(usage.durationSeconds) / CGFloat(maxDuration)
    }

    private func loadData() {
        switch scope {
        case .today:
            loadTodayData()
        case .week:
            loadWeekData()
        }
    }

    private func loadTodayData() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return
        }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) {
            _ = AttentionDaySummaryRecorder.finalizeCompletedDays(
                from: yesterday,
                to: today,
                modelContext: modelContext
            )
        }

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < tomorrow && $0.endTime > today }
        )

        let segments = (try? modelContext.fetch(segmentDescriptor)) ?? []
        let visibleSegments = segments.filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }
        let timerSessions = loadTimerSessions(from: today, to: tomorrow)
        let attentionCorrections = loadAttentionCorrections(from: today, to: tomorrow)
        let breakTransitionIntents = loadBreakTransitionIntents(from: today, to: tomorrow)
        let buckets = TimelineAnalytics.buckets(
            for: today,
            segments: visibleSegments,
            timerSessions: timerSessions
        )
        todayFocusSummary = TimelineAnalytics.summary(
            for: today,
            segments: visibleSegments,
            buckets: buckets,
            timerSessions: timerSessions
        )
        todayAttentionSummary = AttentionAnalytics.summary(
            for: today,
            segments: visibleSegments,
            timerSessions: timerSessions,
            thresholds: AttentionThresholdStore.shared.thresholds,
            breakTransitions: breakTransitionIntents,
            corrections: attentionCorrections
        )

        if !visibleSegments.isEmpty {
            let focusWindows = loadFocusWindows(from: today, to: tomorrow)
            var categoryDurations: [String: Int] = [:]
            for segment in visibleSegments {
                for slice in attributedSlices(for: segment, from: today, to: tomorrow, focusWindows: focusWindows) {
                    categoryDurations[slice.category, default: 0] += slice.durationSeconds
                }
            }
            categoryUsages = makeCategoryUsages(from: categoryDurations)
            return
        }

        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date == today }
        )

        guard let records = try? modelContext.fetch(recordDescriptor) else { return }

        var categoryDurations: [String: Int] = [:]
        for record in records {
            guard !Constants.hiddenLegacyCategories.contains(record.category) else { continue }
            guard !record.bundleIdentifier.hasPrefix(Constants.focusSessionBundlePrefix) else { continue }
            categoryDurations[record.category, default: 0] += record.durationSeconds
        }

        categoryUsages = makeCategoryUsages(from: categoryDurations)
        todayAttentionSummary = .empty
        if todayFocusSummary.totalSeconds == 0 {
            todayFocusSummary = DailyFocusSummary(
                totalSeconds: categoryDurations.values.reduce(0, +),
                switches: 0,
                longestFocusSeconds: categoryDurations.values.max() ?? 0,
                topCategory: categoryDurations.max { $0.value < $1.value }?.key,
                overallScore: categoryDurations.isEmpty ? 0 : 0.35
            )
        }
    }

    private func loadWeekData() {
        let calendar = Calendar.current
        let weekStart = Constants.mondayWeekStart(for: Date(), calendar: calendar)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return
        }

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < weekEnd && $0.endTime > weekStart }
        )
        let segments = ((try? modelContext.fetch(segmentDescriptor)) ?? []).filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }

        var categoryDurations: [String: Int] = [:]
        var dailyDurations: [Date: Int] = [:]

        if !segments.isEmpty {
            let focusWindows = loadFocusWindows(from: weekStart, to: weekEnd)
            for segment in segments {
                for slice in attributedSlices(for: segment, from: weekStart, to: weekEnd, focusWindows: focusWindows) {
                    categoryDurations[slice.category, default: 0] += slice.durationSeconds
                }
                addDailySegmentDuration(segment, from: weekStart, to: weekEnd, to: &dailyDurations)
            }
            weekLongestSessionSeconds = longestSessionSeconds(from: segments, start: weekStart, end: weekEnd)
        } else {
            let recordDescriptor = FetchDescriptor<AppUsageRecord>(
                predicate: #Predicate { $0.date >= weekStart && $0.date < weekEnd }
            )
            for record in (try? modelContext.fetch(recordDescriptor)) ?? [] {
                guard !Constants.hiddenLegacyCategories.contains(record.category) else { continue }
                guard !record.bundleIdentifier.hasPrefix(Constants.focusSessionBundlePrefix) else { continue }
                categoryDurations[record.category, default: 0] += record.durationSeconds
                dailyDurations[calendar.startOfDay(for: record.date), default: 0] += record.durationSeconds
            }
            weekLongestSessionSeconds = dailyDurations.values.max() ?? 0
        }

        categoryUsages = makeCategoryUsages(from: categoryDurations)
        weeklyDailyTotals = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return (date: day, durationSeconds: dailyDurations[calendar.startOfDay(for: day)] ?? 0)
        }
    }

    private func longestSessionSeconds(from segments: [AppUsageSegment], start: Date, end: Date) -> Int {
        let clipped: [(start: Date, end: Date, category: String)] = segments.compactMap { segment in
            let clippedStart = max(segment.startTime, start)
            let clippedEnd = min(segment.endTime, end)
            guard clippedEnd > clippedStart else { return nil }
            return (clippedStart, clippedEnd, segment.category)
        }
        .sorted { $0.start < $1.start }

        let maxGap: TimeInterval = 120
        var longest: TimeInterval = 0
        var runStart: Date?
        var runEnd: Date?
        var runCategory: String?

        for segment in clipped {
            if let category = runCategory,
               category == segment.category,
               let currentEnd = runEnd,
               segment.start.timeIntervalSince(currentEnd) <= maxGap {
                runEnd = segment.end
            } else {
                if let start = runStart, let end = runEnd {
                    longest = max(longest, end.timeIntervalSince(start))
                }
                runStart = segment.start
                runEnd = segment.end
                runCategory = segment.category
            }
        }

        if let start = runStart, let end = runEnd {
            longest = max(longest, end.timeIntervalSince(start))
        }

        return Int(longest)
    }

    private func addDailySegmentDuration(
        _ segment: AppUsageSegment,
        from start: Date,
        to end: Date,
        to dailyDurations: inout [Date: Int]
    ) {
        let calendar = Calendar.current
        var cursor = max(segment.startTime, start)
        let segmentEnd = min(segment.endTime, end)
        while cursor < segmentEnd {
            let day = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let chunkEnd = min(segmentEnd, nextDay)
            let duration = Int(chunkEnd.timeIntervalSince(cursor))
            if duration > 0 {
                dailyDurations[day, default: 0] += duration
            }
            cursor = chunkEnd
        }
    }

    private func clippedDuration(_ segment: AppUsageSegment, from start: Date, to end: Date) -> Int {
        let clippedStart = max(segment.startTime, start)
        let clippedEnd = min(segment.endTime, end)
        guard clippedEnd > clippedStart else { return 0 }
        return Int(clippedEnd.timeIntervalSince(clippedStart))
    }

    private func loadFocusWindows(from start: Date, to end: Date) -> [SummaryPomodoroFocusWindow] {
        loadTimerSessions(from: start, to: end).compactMap { session in
            guard isCompletedPomodoro(session),
                  let focusEnd = focusEnd(for: session) else {
                return nil
            }

            let windowStart = max(session.startedAt, start)
            let windowEnd = min(focusEnd, end)
            guard windowEnd > windowStart else { return nil }

            return SummaryPomodoroFocusWindow(
                start: windowStart,
                end: windowEnd,
                category: session.category ?? Constants.defaultFocusCategory
            )
        }
    }

    private func loadTimerSessions(from start: Date, to end: Date) -> [FocusSession] {
        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func attributedSlices(
        for segment: AppUsageSegment,
        from start: Date,
        to end: Date,
        focusWindows: [SummaryPomodoroFocusWindow]
    ) -> [(category: String, durationSeconds: Int)] {
        let segmentStart = max(segment.startTime, start)
        let segmentEnd = min(segment.endTime, end)
        guard segmentEnd > segmentStart else { return [] }

        var remaining: [(start: Date, end: Date)] = [(segmentStart, segmentEnd)]
        var slices: [(category: String, durationSeconds: Int)] = []

        for window in focusWindows {
            let overlapStart = max(segmentStart, window.start)
            let overlapEnd = min(segmentEnd, window.end)
            guard overlapEnd > overlapStart else { continue }

            let duration = Int(overlapEnd.timeIntervalSince(overlapStart))
            if duration > 0 {
                slices.append((window.category, duration))
            }

            remaining = remaining.flatMap { interval -> [(start: Date, end: Date)] in
                let clippedStart = max(interval.start, overlapStart)
                let clippedEnd = min(interval.end, overlapEnd)
                guard clippedEnd > clippedStart else { return [interval] }

                var parts: [(start: Date, end: Date)] = []
                if interval.start < clippedStart {
                    parts.append((interval.start, clippedStart))
                }
                if clippedEnd < interval.end {
                    parts.append((clippedEnd, interval.end))
                }
                return parts
            }
        }

        for interval in remaining {
            let duration = Int(interval.end.timeIntervalSince(interval.start))
            guard duration > 0 else { continue }
            slices.append((segment.category, duration))
        }

        return slices
    }

    private func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    private func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }

    private func makeCategoryUsages(from durations: [String: Int]) -> [CategoryUsage] {
        durations
            .sorted { $0.value > $1.value }
            .map { key, value in
                CategoryUsage(
                    category: key,
                    emoji: Constants.categoryEmoji(for: key),
                    color: Constants.categoryColor(for: key),
                    durationSeconds: value
                )
            }
    }

    private func shortDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    private func formatKoreanDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return "\(h)시간 \(m)분"
    }

    private func formatMetricDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(format: "%d시간 %02d분", h, m)
        }
        return "\(m)분"
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}
