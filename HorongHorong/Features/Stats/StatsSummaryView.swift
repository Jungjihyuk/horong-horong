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

struct StatsSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var categoryUsages: [CategoryUsage] = []

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                Group {
                    if categoryUsages.isEmpty {
                        emptyState
                    } else {
                        usageBars
                    }
                }
                .padding(.trailing, 12)
            }
            detailButton
        }
        .onAppear { loadTodayData() }
    }

    private var header: some View {
        HStack {
            Label("오늘의 사용 시간", systemImage: "chart.bar")
                .font(.headline)
            Spacer()
            Text("총 \(totalFormatted)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("아직 기록된 데이터가 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var usageBars: some View {
        VStack(spacing: 6) {
            ForEach(categoryUsages) { usage in
                HStack(spacing: 8) {
                    Text(usage.emoji)
                        .frame(width: 20)
                    Text(usage.category)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(usage.color.opacity(0.7))
                            .frame(width: barWidth(for: usage, in: geo.size.width))
                    }
                    .frame(height: 12)

                    Text(usage.formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var detailButton: some View {
        Button {
            openWindow(id: "stats-detail")
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
            Label("📈 상세 보기", systemImage: "chart.bar.xaxis")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var totalFormatted: String {
        let total = categoryUsages.reduce(0) { $0 + $1.durationSeconds }
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)시간 \(m)분"
    }

    private func barWidth(for usage: CategoryUsage, in maxWidth: CGFloat) -> CGFloat {
        let maxDuration = categoryUsages.map(\.durationSeconds).max() ?? 1
        guard maxDuration > 0 else { return 0 }
        return maxWidth * CGFloat(usage.durationSeconds) / CGFloat(maxDuration)
    }

    private func loadTodayData() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return
        }

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < tomorrow && $0.endTime > today }
        )

        let segments = (try? modelContext.fetch(segmentDescriptor)) ?? []
        let visibleSegments = segments.filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }

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
    }

    private func clippedDuration(_ segment: AppUsageSegment, from start: Date, to end: Date) -> Int {
        let clippedStart = max(segment.startTime, start)
        let clippedEnd = min(segment.endTime, end)
        guard clippedEnd > clippedStart else { return 0 }
        return Int(clippedEnd.timeIntervalSince(clippedStart))
    }

    private func loadFocusWindows(from start: Date, to end: Date) -> [SummaryPomodoroFocusWindow] {
        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )

        return ((try? modelContext.fetch(descriptor)) ?? []).compactMap { session in
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
}
