import Foundation
import SwiftData

@Model
final class StatsAggregateCache {
    var id: UUID
    var scope: String
    var periodStart: Date
    var periodEnd: Date
    var sourceFingerprint: String
    var payload: Data
    var createdAt: Date
    var updatedAt: Date

    init(scope: String, periodStart: Date, periodEnd: Date, sourceFingerprint: String, payload: Data) {
        self.id = UUID()
        self.scope = scope
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.sourceFingerprint = sourceFingerprint
        self.payload = payload
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct StatsDailyCategoryAggregate: Codable, Hashable, Identifiable {
    var id: String { "\(Int(day.timeIntervalSince1970))-\(category)" }
    let day: Date
    let category: String
    let durationSeconds: Int
}

struct StatsDailyFocusAggregate: Codable, Hashable, Identifiable {
    var id: Int { Int(day.timeIntervalSince1970) }
    let day: Date
    let level: String
}

struct StatsAggregateSnapshot: Codable, Hashable {
    let dailyCategories: [StatsDailyCategoryAggregate]
    let dailyFocusLevels: [StatsDailyFocusAggregate]

    var isEmpty: Bool {
        dailyCategories.isEmpty
    }

    var categoryDurations: [String: Int] {
        dailyCategories.reduce(into: [:]) { result, item in
            result[item.category, default: 0] += item.durationSeconds
        }
    }

    var dailyDurations: [Date: Int] {
        dailyCategories.reduce(into: [:]) { result, item in
            result[item.day, default: 0] += item.durationSeconds
        }
    }
}

enum StatsAggregateScope {
    static let weekly = "weekly"
    static let monthly = "monthly"

    static func value(for mode: StatsViewMode) -> String? {
        switch mode {
        case .daily:
            return nil
        case .weekly:
            return weekly
        case .monthly:
            return monthly
        }
    }
}

enum StatsAggregateCacheCodec {
    static func encode(_ snapshot: StatsAggregateSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Data) -> StatsAggregateSnapshot? {
        try? JSONDecoder().decode(StatsAggregateSnapshot.self, from: data)
    }
}

enum StatsAggregateBuilder {
    private struct FocusWindow {
        let start: Date
        let end: Date
        let category: String
    }

    private struct UsageSlice {
        let category: String
        let durationSeconds: Int
        let start: Date
        let end: Date
    }

    static func fingerprint(records: [AppUsageRecord], sessions: [FocusSession]) -> String {
        let recordPart = records
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.bundleIdentifier != $1.bundleIdentifier { return $0.bundleIdentifier < $1.bundleIdentifier }
                return $0.category < $1.category
            }
            .map {
                [
                    "r",
                    String(Int($0.date.timeIntervalSince1970)),
                    $0.bundleIdentifier,
                    $0.category,
                    String($0.durationSeconds),
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        let sessionPart = sessions
            .sorted { $0.startedAt < $1.startedAt }
            .map {
                [
                    "s",
                    String(Int($0.startedAt.timeIntervalSince1970)),
                    String(Int(($0.endedAt ?? .distantPast).timeIntervalSince1970)),
                    $0.category ?? Constants.defaultFocusCategory,
                    String($0.focusMinutes),
                    $0.completed ? "1" : "0",
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        return "\(recordPart)#\(sessionPart)"
    }

    static func build(
        mode: StatsViewMode,
        start: Date,
        end: Date,
        records: [AppUsageRecord],
        segments: [AppUsageSegment],
        timerSessions: [FocusSession]
    ) -> StatsAggregateSnapshot {
        let dailyCategories: [StatsDailyCategoryAggregate]
        if segments.isEmpty {
            dailyCategories = recordDailyCategories(records)
        } else {
            dailyCategories = segmentDailyCategories(
                segments,
                start: start,
                end: end,
                timerSessions: timerSessions
            )
        }

        let focusLevels: [StatsDailyFocusAggregate]
        if mode == .weekly, !segments.isEmpty {
            focusLevels = weeklyFocusLevels(start: start, segments: segments, timerSessions: timerSessions)
        } else {
            focusLevels = []
        }

        return StatsAggregateSnapshot(
            dailyCategories: dailyCategories,
            dailyFocusLevels: focusLevels
        )
    }

    private static func recordDailyCategories(_ records: [AppUsageRecord]) -> [StatsDailyCategoryAggregate] {
        var grouped: [String: (day: Date, category: String, seconds: Int)] = [:]
        let calendar = Calendar.current

        for record in records {
            guard !Constants.hiddenLegacyCategories.contains(record.category),
                  !record.bundleIdentifier.hasPrefix(Constants.focusSessionBundlePrefix) else {
                continue
            }

            let day = calendar.startOfDay(for: record.date)
            let key = "\(Int(day.timeIntervalSince1970))-\(record.category)"
            if let existing = grouped[key] {
                grouped[key] = (existing.day, existing.category, existing.seconds + record.durationSeconds)
            } else {
                grouped[key] = (day, record.category, record.durationSeconds)
            }
        }

        return grouped.values
            .filter { $0.seconds > 0 }
            .map { StatsDailyCategoryAggregate(day: $0.day, category: $0.category, durationSeconds: $0.seconds) }
            .sorted {
                if $0.day != $1.day { return $0.day < $1.day }
                return $0.category < $1.category
            }
    }

    private static func segmentDailyCategories(
        _ segments: [AppUsageSegment],
        start: Date,
        end: Date,
        timerSessions: [FocusSession]
    ) -> [StatsDailyCategoryAggregate] {
        var grouped: [String: (day: Date, category: String, seconds: Int)] = [:]

        for segment in segments where !Constants.hiddenLegacyCategories.contains(segment.category) {
            let slices = attributedSlices(for: segment, start: start, end: end, timerSessions: timerSessions)
            for slice in slices {
                for dailySlice in splitByDay(slice) {
                    let key = "\(Int(dailySlice.day.timeIntervalSince1970))-\(dailySlice.category)"
                    if let existing = grouped[key] {
                        grouped[key] = (existing.day, existing.category, existing.seconds + dailySlice.durationSeconds)
                    } else {
                        grouped[key] = (dailySlice.day, dailySlice.category, dailySlice.durationSeconds)
                    }
                }
            }
        }

        return grouped.values
            .filter { $0.seconds > 0 }
            .map { StatsDailyCategoryAggregate(day: $0.day, category: $0.category, durationSeconds: $0.seconds) }
            .sorted {
                if $0.day != $1.day { return $0.day < $1.day }
                return $0.category < $1.category
            }
    }

    private static func weeklyFocusLevels(
        start: Date,
        segments: [AppUsageSegment],
        timerSessions: [FocusSession]
    ) -> [StatsDailyFocusAggregate] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
            let daySegments = segments.filter {
                $0.startTime < dayEnd && $0.endTime > day
            }
            let buckets = TimelineAnalytics.buckets(
                for: day,
                segments: daySegments,
                timerSessions: timerSessions
            )
            let summary = TimelineAnalytics.summary(
                for: day,
                segments: daySegments,
                buckets: buckets,
                timerSessions: timerSessions
            )
            return StatsDailyFocusAggregate(day: day, level: levelValue(summary.level))
        }
    }

    private static func splitByDay(_ slice: UsageSlice) -> [(day: Date, category: String, durationSeconds: Int)] {
        let calendar = Calendar.current
        var result: [(day: Date, category: String, durationSeconds: Int)] = []
        var cursor = slice.start

        while cursor < slice.end {
            let day = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let chunkEnd = min(slice.end, nextDay)
            let seconds = Int(chunkEnd.timeIntervalSince(cursor))
            if seconds > 0 {
                result.append((day, slice.category, seconds))
            }
            cursor = chunkEnd
        }

        return result
    }

    private static func attributedSlices(
        for segment: AppUsageSegment,
        start: Date,
        end: Date,
        timerSessions: [FocusSession]
    ) -> [UsageSlice] {
        let segmentStart = max(segment.startTime, start)
        let segmentEnd = min(segment.endTime, end)
        guard segmentEnd > segmentStart else { return [] }

        var remaining: [(start: Date, end: Date)] = [(segmentStart, segmentEnd)]
        var slices: [UsageSlice] = []

        for window in focusWindows(from: segmentStart, to: segmentEnd, timerSessions: timerSessions) {
            let overlapStart = max(segmentStart, window.start)
            let overlapEnd = min(segmentEnd, window.end)
            guard overlapEnd > overlapStart else { continue }

            slices.append(UsageSlice(
                category: window.category,
                durationSeconds: Int(overlapEnd.timeIntervalSince(overlapStart)),
                start: overlapStart,
                end: overlapEnd
            ))

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
            let seconds = Int(interval.end.timeIntervalSince(interval.start))
            guard seconds > 0 else { continue }
            slices.append(UsageSlice(
                category: segment.category,
                durationSeconds: seconds,
                start: interval.start,
                end: interval.end
            ))
        }

        return slices
    }

    private static func focusWindows(
        from start: Date,
        to end: Date,
        timerSessions: [FocusSession]
    ) -> [FocusWindow] {
        var windows: [FocusWindow] = []
        for session in timerSessions {
            guard let focusEnd = focusEnd(for: session) else { continue }
            if focusEnd <= start { continue }
            if session.startedAt >= end { break }
            guard isCompletedPomodoro(session) else { continue }

            let windowStart = max(session.startedAt, start)
            let windowEnd = min(focusEnd, end)
            guard windowEnd > windowStart else { continue }

            windows.append(FocusWindow(
                start: windowStart,
                end: windowEnd,
                category: session.category ?? Constants.defaultFocusCategory
            ))
        }
        return windows
    }

    private static func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    private static func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }

    private static func levelValue(_ level: DailyFocusSummary.Level) -> String {
        switch level {
        case .focused:
            return "focused"
        case .moderate:
            return "moderate"
        case .scattered:
            return "scattered"
        case .empty:
            return "empty"
        }
    }
}
