import Foundation
import SwiftData

@MainActor
final class SwiftDataStatsSummaryRepository: StatsSummaryRepository {
    private struct FocusWindow {
        let start: Date
        let end: Date
        let category: String
    }

    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func todaySummary(on date: Date) -> StatsTodaySummary {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return emptyTodaySummary
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart) {
            _ = AttentionDaySummaryRecorder.finalizeCompletedDays(
                from: yesterday,
                to: dayStart,
                modelContext: context
            )
        }

        let segments = fetchSegments(from: dayStart, to: dayEnd)
        let sessions = fetchSessions(from: dayStart, to: dayEnd)
        let nudge = FocusNudgeSnapshot.make(day: dayStart, modelContext: context)
        var focus = focusSummary(for: dayStart, segments: segments, sessions: sessions)
        let categoryDurations: [String: Int]

        if segments.isEmpty {
            categoryDurations = recordDurations(from: dayStart, to: dayEnd)
            if focus.totalSeconds == 0 {
                focus = StatsFocusSummary(
                    totalSeconds: categoryDurations.values.reduce(0, +),
                    switches: 0,
                    longestFocusSeconds: categoryDurations.values.max() ?? 0,
                    topCategory: categoryDurations.max { $0.value < $1.value }?.key,
                    overallScore: categoryDurations.isEmpty ? 0 : 0.35
                )
            }
        } else {
            categoryDurations = attributedDurations(
                segments: segments,
                from: dayStart,
                to: dayEnd,
                focusWindows: focusWindows(from: sessions, start: dayStart, end: dayEnd)
            )
        }

        return StatsTodaySummary(
            categories: categories(from: categoryDurations),
            focus: focus,
            hasSegmentDetails: !segments.isEmpty,
            nudge: StatsSummaryNudge(badge: nudge.nudge.badge, message: nudge.nudge.message)
        )
    }

    func weekSummary(containing date: Date) -> StatsWeekSummary {
        let weekStart = Constants.mondayWeekStart(for: date, calendar: calendar)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return StatsWeekSummary(categories: [], days: [], longestSessionSeconds: 0)
        }

        let segments = fetchSegments(from: weekStart, to: weekEnd)
        var categoryDurations: [String: Int] = [:]
        var dailyDurations: [Date: Int] = [:]
        let longest: Int

        if segments.isEmpty {
            let records = fetchRecords(from: weekStart, to: weekEnd)
            for record in records {
                categoryDurations[record.category, default: 0] += record.durationSeconds
                dailyDurations[calendar.startOfDay(for: record.date), default: 0] += record.durationSeconds
            }
            longest = dailyDurations.values.max() ?? 0
        } else {
            let sessions = fetchSessions(from: weekStart, to: weekEnd)
            categoryDurations = attributedDurations(
                segments: segments,
                from: weekStart,
                to: weekEnd,
                focusWindows: focusWindows(from: sessions, start: weekStart, end: weekEnd)
            )
            for segment in segments {
                addDailyDuration(segment, from: weekStart, to: weekEnd, to: &dailyDurations)
            }
            longest = longestSessionSeconds(segments, from: weekStart, to: weekEnd)
        }

        let days = (0..<7).compactMap { offset -> StatsDayDuration? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return StatsDayDuration(
                date: day,
                durationSeconds: dailyDurations[calendar.startOfDay(for: day)] ?? 0
            )
        }
        return StatsWeekSummary(
            categories: categories(from: categoryDurations),
            days: days,
            longestSessionSeconds: longest
        )
    }

    private var emptyTodaySummary: StatsTodaySummary {
        StatsTodaySummary(
            categories: [],
            focus: StatsFocusSummary(
                totalSeconds: 0,
                switches: 0,
                longestFocusSeconds: 0,
                topCategory: nil,
                overallScore: 0
            ),
            hasSegmentDetails: false,
            nudge: nil
        )
    }

    private func fetchSegments(from start: Date, to end: Date) -> [AppUsageSegment] {
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }
    }

    private func fetchRecords(from start: Date, to end: Date) -> [AppUsageRecord] {
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return ((try? context.fetch(descriptor)) ?? []).filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
                && !$0.bundleIdentifier.hasPrefix(Constants.focusSessionBundlePrefix)
        }
    }

    private func recordDurations(from start: Date, to end: Date) -> [String: Int] {
        fetchRecords(from: start, to: end).reduce(into: [:]) {
            $0[$1.category, default: 0] += $1.durationSeconds
        }
    }

    private func fetchSessions(from start: Date, to end: Date) -> [FocusSession] {
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func focusWindows(from sessions: [FocusSession], start: Date, end: Date) -> [FocusWindow] {
        sessions.compactMap { session in
            guard isCompletedPomodoro(session), let focusEnd = focusEnd(for: session) else { return nil }
            let windowStart = max(session.startedAt, start)
            let windowEnd = min(focusEnd, end)
            guard windowEnd > windowStart else { return nil }
            return FocusWindow(
                start: windowStart,
                end: windowEnd,
                category: session.category ?? Constants.defaultFocusCategory
            )
        }
    }

    private func attributedDurations(
        segments: [AppUsageSegment],
        from start: Date,
        to end: Date,
        focusWindows: [FocusWindow]
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        for segment in segments {
            let segmentStart = max(segment.startTime, start)
            let segmentEnd = min(segment.endTime, end)
            guard segmentEnd > segmentStart else { continue }
            var remaining = [(start: segmentStart, end: segmentEnd)]

            for window in focusWindows {
                let overlapStart = max(segmentStart, window.start)
                let overlapEnd = min(segmentEnd, window.end)
                guard overlapEnd > overlapStart else { continue }
                result[window.category, default: 0] += Int(overlapEnd.timeIntervalSince(overlapStart))
                remaining = remaining.flatMap { interval in
                    let clippedStart = max(interval.start, overlapStart)
                    let clippedEnd = min(interval.end, overlapEnd)
                    guard clippedEnd > clippedStart else { return [interval] }
                    var parts: [(start: Date, end: Date)] = []
                    if interval.start < clippedStart { parts.append((interval.start, clippedStart)) }
                    if clippedEnd < interval.end { parts.append((clippedEnd, interval.end)) }
                    return parts
                }
            }
            for interval in remaining {
                result[segment.category, default: 0] += Int(interval.end.timeIntervalSince(interval.start))
            }
        }
        return result
    }

    private func focusSummary(
        for day: Date,
        segments: [AppUsageSegment],
        sessions: [FocusSession]
    ) -> StatsFocusSummary {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return emptyTodaySummary.focus
        }
        let sorted = segments.compactMap { segment -> (start: Date, end: Date, category: String)? in
            let start = max(segment.startTime, dayStart)
            let end = min(segment.endTime, dayEnd)
            return end > start ? (start, end, segment.category) : nil
        }.sorted { $0.start < $1.start }
        var switches = 0
        var previous: (start: Date, end: Date, category: String)?
        for segment in sorted {
            if let previous,
               segment.start.timeIntervalSince(previous.end) >= 0,
               segment.start.timeIntervalSince(previous.end) <= 120,
               previous.category != segment.category {
                switches += 1
            }
            previous = segment
        }

        var longest: TimeInterval = 0
        var runDuration: TimeInterval = 0
        var runEnd: Date?
        var runCategory: String?
        var totals: [String: Int] = [:]
        for segment in sorted {
            let duration = segment.end.timeIntervalSince(segment.start)
            totals[segment.category, default: 0] += Int(duration)
            if runCategory == segment.category,
               let runEnd,
               segment.start.timeIntervalSince(runEnd) <= 120 {
                runDuration += duration
            } else {
                longest = max(longest, runDuration)
                runDuration = duration
                runCategory = segment.category
            }
            runEnd = segment.end
        }
        longest = max(longest, runDuration)

        let bucketSeconds: TimeInterval = 30 * 60
        var bucketDurations: [Int: [String: Int]] = [:]
        var bucketSwitches: [Int: Int] = [:]
        var lastCategory: String?
        for segment in sorted {
            var cursor = segment.start
            while cursor < segment.end {
                let index = Int(floor(cursor.timeIntervalSince(dayStart) / bucketSeconds))
                let chunkEnd = min(
                    segment.end,
                    dayStart.addingTimeInterval(Double(index + 1) * bucketSeconds)
                )
                bucketDurations[index, default: [:]][segment.category, default: 0]
                    += Int(chunkEnd.timeIntervalSince(cursor))
                cursor = chunkEnd
            }
            if let lastCategory, lastCategory != segment.category {
                let isInsideTimer = sessions.contains {
                    guard let end = $0.endedAt else { return false }
                    return segment.start >= $0.startedAt && segment.start < end
                }
                if !CategoryPairStore.shared.contains(lastCategory, segment.category), !isInsideTimer {
                    let index = Int(floor(segment.start.timeIntervalSince(dayStart) / bucketSeconds))
                    bucketSwitches[index, default: 0] += 1
                }
            }
            lastCategory = segment.category
        }

        var weightedScore = 0.0
        var totalWeight = 0
        for (index, durations) in bucketDurations {
            let total = durations.values.reduce(0, +)
            let fractions = durations.values.map { Double($0) / Double(max(1, total)) }
            let count = Double(fractions.count)
            let concentration: Double
            if count <= 1 {
                concentration = 1
            } else {
                let hhi = fractions.reduce(0) { $0 + $1 * $1 }
                let minimum = 1 / count
                concentration = max(0, min(1, (hhi - minimum) / max(0.0001, 1 - minimum)))
            }
            let switchPenalty = max(0, 1 - Double(bucketSwitches[index, default: 0]) / 6)
            let score = concentration * switchPenalty
            weightedScore += score * Double(total)
            totalWeight += total
        }

        return StatsFocusSummary(
            totalSeconds: totals.values.reduce(0, +),
            switches: switches,
            longestFocusSeconds: Int(longest),
            topCategory: totals.max { $0.value < $1.value }?.key,
            overallScore: totalWeight > 0 ? weightedScore / Double(totalWeight) : 0
        )
    }

    private func addDailyDuration(
        _ segment: AppUsageSegment,
        from start: Date,
        to end: Date,
        to result: inout [Date: Int]
    ) {
        var cursor = max(segment.startTime, start)
        let segmentEnd = min(segment.endTime, end)
        while cursor < segmentEnd {
            let day = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let chunkEnd = min(segmentEnd, nextDay)
            result[day, default: 0] += Int(chunkEnd.timeIntervalSince(cursor))
            cursor = chunkEnd
        }
    }

    private func longestSessionSeconds(_ segments: [AppUsageSegment], from start: Date, to end: Date) -> Int {
        let clipped = segments.compactMap { segment -> (Date, Date, String)? in
            let clippedStart = max(segment.startTime, start)
            let clippedEnd = min(segment.endTime, end)
            return clippedEnd > clippedStart ? (clippedStart, clippedEnd, segment.category) : nil
        }.sorted { $0.0 < $1.0 }
        var longest: TimeInterval = 0
        var runStart: Date?
        var runEnd: Date?
        var runCategory: String?
        for segment in clipped {
            if runCategory == segment.2,
               let currentEnd = runEnd,
               segment.0.timeIntervalSince(currentEnd) <= 120 {
                runEnd = segment.1
            } else {
                if let runStart, let runEnd { longest = max(longest, runEnd.timeIntervalSince(runStart)) }
                runStart = segment.0
                runEnd = segment.1
                runCategory = segment.2
            }
        }
        if let runStart, let runEnd { longest = max(longest, runEnd.timeIntervalSince(runStart)) }
        return Int(longest)
    }

    private func categories(from durations: [String: Int]) -> [StatsCategoryDuration] {
        durations
            .sorted { $0.value > $1.value }
            .map { StatsCategoryDuration(category: $0.key, durationSeconds: $0.value) }
    }

    private func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        return expectedSeconds > 0
            && (session.completed || endedAt.timeIntervalSince(session.startedAt) >= Double(expectedSeconds))
    }

    private func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expected = session.startedAt.addingTimeInterval(Double(max(0, session.focusMinutes) * 60))
        return min(endedAt, expected)
    }
}
