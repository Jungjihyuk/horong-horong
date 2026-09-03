import Foundation
import SwiftData

@MainActor
enum AppClassificationService {
    private struct UsageDayKey: Hashable {
        let bundleIdentifier: String
        let date: Date
    }

    private struct DailyCategoryTotal {
        var appName: String
        var durationSeconds: Int
        var latestEndTime: Date
    }

    static func productivityManagementAppUsages(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [ProductivityManagementAppUsage] {
        guard end > start else { return [] }
        return productivityManagementAppUsages(
            activeIntervals: [DateInterval(start: start, end: end)],
            modelContext: modelContext
        )
    }

    static func productivityManagementAppUsages(
        activeIntervals: [DateInterval],
        modelContext: ModelContext
    ) -> [ProductivityManagementAppUsage] {
        let intervals = normalized(activeIntervals)
        guard let start = intervals.first?.start,
              let end = intervals.last?.end else { return [] }
        let managementCategory = Constants.productivityManagementAppCategory
        let legacyCategory = Constants.legacySupportAppCategory
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                ($0.category == managementCategory || $0.category == legacyCategory)
                    && $0.startTime < end
                    && $0.endTime > start
            }
        )
        let segments = (try? modelContext.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: segments, by: \.bundleIdentifier)

        return grouped.compactMap { bundleIdentifier, appSegments in
            let durationSeconds = appSegments.reduce(0) { total, segment in
                total + clippedDuration(of: segment, to: intervals)
            }
            guard durationSeconds >= Constants.productivityManagementReflectionThresholdSeconds else {
                return nil
            }
            return ProductivityManagementAppUsage(
                bundleIdentifier: bundleIdentifier,
                appName: appSegments.last?.appName ?? bundleIdentifier,
                durationSeconds: durationSeconds
            )
        }
        .sorted {
            if $0.durationSeconds != $1.durationSeconds {
                return $0.durationSeconds > $1.durationSeconds
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    static func prepareProductivityManagementAppSessionClassification(
        bundleIdentifier: String,
        from start: Date,
        to end: Date,
        category: String,
        modelContext: ModelContext
    ) throws {
        guard end > start,
              !Constants.isProductivityManagementCategory(category) else {
            return
        }
        let managementCategory = Constants.productivityManagementAppCategory
        let legacyCategory = Constants.legacySupportAppCategory
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier
                    && ($0.category == managementCategory || $0.category == legacyCategory)
                    && $0.startTime < end
                    && $0.endTime > start
            }
        )

        for segment in try modelContext.fetch(descriptor) {
            let originalStart = segment.startTime
            let originalEnd = segment.endTime
            let classifiedStart = max(start, originalStart)
            let classifiedEnd = min(end, originalEnd)
            guard classifiedEnd > classifiedStart else { continue }
            let originalCategory = segment.category

            if originalStart < classifiedStart {
                modelContext.insert(AppUsageSegment(
                    appName: segment.appName,
                    bundleIdentifier: segment.bundleIdentifier,
                    category: originalCategory,
                    startTime: originalStart,
                    endTime: classifiedStart,
                    isManual: segment.isManual,
                    isUserModified: segment.isUserModified
                ))
            }
            if classifiedEnd < originalEnd {
                modelContext.insert(AppUsageSegment(
                    appName: segment.appName,
                    bundleIdentifier: segment.bundleIdentifier,
                    category: originalCategory,
                    startTime: classifiedEnd,
                    endTime: originalEnd,
                    isManual: segment.isManual,
                    isUserModified: segment.isUserModified
                ))
            }

            segment.startTime = classifiedStart
            segment.endTime = classifiedEnd
            segment.category = category
            segment.isUserModified = true
        }
    }

    static func unclassifiedApps(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [UnclassifiedAppUsage] {
        guard end > start else { return [] }
        return unclassifiedApps(
            activeIntervals: [DateInterval(start: start, end: end)],
            modelContext: modelContext
        )
    }

    static func unclassifiedAssessment(
        activeIntervals: [DateInterval],
        modelContext: ModelContext
    ) -> UnclassifiedAppAssessment {
        let intervals = normalized(activeIntervals)
        guard let start = intervals.first?.start,
              let end = intervals.last?.end else {
            return UnclassifiedAppAssessment(
                apps: [],
                recordedAppSeconds: 0,
                unclassifiedAppSeconds: 0
            )
        }
        let segments = (try? modelContext.fetch(
            FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )) ?? []
        var recordedAppSeconds = 0
        var unclassifiedAppSeconds = 0
        for interval in intervals {
            let observation = PomodoroSessionObservationBuilder.observation(
                from: interval.start,
                to: interval.end,
                segments: segments
            )
            recordedAppSeconds += observation.attributedSeconds
            unclassifiedAppSeconds += observation.unclassifiedSeconds
        }
        return UnclassifiedAppAssessment(
            apps: unclassifiedApps(
                activeIntervals: intervals,
                modelContext: modelContext
            ),
            recordedAppSeconds: recordedAppSeconds,
            unclassifiedAppSeconds: unclassifiedAppSeconds
        )
    }

    static func unclassifiedApps(
        activeIntervals: [DateInterval],
        modelContext: ModelContext
    ) -> [UnclassifiedAppUsage] {
        let intervals = normalized(activeIntervals)
        guard let start = intervals.first?.start,
              let end = intervals.last?.end else { return [] }
        let unclassifiedCategory = Constants.unclassifiedAppCategory
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.category == unclassifiedCategory
                    && $0.startTime < end
                    && $0.endTime > start
            }
        )
        let excludedBundleIdentifiers = excludedBundleIdentifiers(modelContext: modelContext)
        let segments = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            !excludedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let grouped = Dictionary(grouping: segments, by: \.bundleIdentifier)

        return grouped.map { bundleIdentifier, segments in
            let duration = segments.reduce(0) { total, segment in
                total + clippedDuration(of: segment, to: intervals)
            }
            return UnclassifiedAppUsage(
                bundleIdentifier: bundleIdentifier,
                appName: segments.last?.appName ?? bundleIdentifier,
                durationSeconds: duration
            )
        }
        .filter { $0.durationSeconds > 0 }
        .sorted {
            if $0.durationSeconds != $1.durationSeconds {
                return $0.durationSeconds > $1.durationSeconds
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    private static func normalized(_ intervals: [DateInterval]) -> [DateInterval] {
        intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
    }

    private static func clippedDuration(
        of segment: AppUsageSegment,
        to intervals: [DateInterval]
    ) -> Int {
        intervals.reduce(0) { total, interval in
            let start = max(interval.start, segment.startTime)
            let end = min(interval.end, segment.endTime)
            return total + max(0, Int(end.timeIntervalSince(start)))
        }
    }

    static func allUnclassifiedApps(
        modelContext: ModelContext
    ) -> [UnclassifiedAppUsage] {
        let unclassifiedCategory = Constants.unclassifiedAppCategory
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.category == unclassifiedCategory }
        )
        let excludedBundleIdentifiers = excludedBundleIdentifiers(modelContext: modelContext)
        let segments = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            !excludedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let grouped = Dictionary(grouping: segments, by: \.bundleIdentifier)

        return grouped.map { bundleIdentifier, segments in
            UnclassifiedAppUsage(
                bundleIdentifier: bundleIdentifier,
                appName: segments.last?.appName ?? bundleIdentifier,
                durationSeconds: segments.reduce(0) { $0 + $1.durationSeconds }
            )
        }
        .sorted {
            if $0.durationSeconds != $1.durationSeconds {
                return $0.durationSeconds > $1.durationSeconds
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    static func apply(
        choices: [String: UnclassifiedAppChoice],
        apps: [UnclassifiedAppUsage],
        modelContext: ModelContext
    ) throws {
        let appsByBundleID = Dictionary(
            uniqueKeysWithValues: apps.map { ($0.bundleIdentifier, $0) }
        )
        for (bundleIdentifier, choice) in choices {
            guard let app = appsByBundleID[bundleIdentifier] else { continue }
            switch choice {
            case let .category(category):
                try prepareClassification(
                    bundleIdentifier: bundleIdentifier,
                    appName: app.appName,
                    category: category,
                    modelContext: modelContext
                )
            case .excluded:
                try prepareExclusion(
                    bundleIdentifier: bundleIdentifier,
                    appName: app.appName,
                    modelContext: modelContext
                )
            }
        }
    }

    static func classify(
        bundleIdentifier: String,
        appName: String,
        category: String,
        modelContext: ModelContext
    ) throws {
        try prepareClassification(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: category,
            modelContext: modelContext
        )
        try modelContext.save()
        CategoryManager.shared.setUserRule(
            bundleIdentifier: bundleIdentifier,
            category: category
        )
        postUsageChange()
    }

    static func reclassifyUnclassifiedUsage(
        bundleIdentifier: String,
        category: String,
        modelContext: ModelContext
    ) throws {
        let unclassifiedCategory = Constants.unclassifiedAppCategory
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.category == unclassifiedCategory
            }
        )
        for segment in try modelContext.fetch(segmentDescriptor) {
            segment.category = category
        }

        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.category == unclassifiedCategory
            }
        )
        for record in try modelContext.fetch(recordDescriptor) {
            record.category = category
        }

        try modelContext.save()
        postUsageChange()
    }

    @discardableResult
    static func reclassifyExistingUsage(
        ruleBundleIdentifier: String,
        category: String,
        modelContext: ModelContext
    ) throws -> Int {
        let websiteDomain = WebsiteCategoryRule.domain(from: ruleBundleIdentifier)
        let websiteDomains = websiteDomain.map(Constants.websiteRuleDomains(for:)) ?? []
        let legacyBundleSuffixes = websiteDomain.map(
            Constants.legacyWebsiteTrackedBundleSuffixes(for:)
        ) ?? []
        let segments = try modelContext.fetch(FetchDescriptor<AppUsageSegment>())
        let matchingSegments = segments.filter { segment in
            if websiteDomain != nil {
                return websiteDomains.contains { domain in
                    WebsiteCategoryRule.matchesTrackedBundleIdentifier(
                        segment.bundleIdentifier,
                        domain: domain
                    )
                } || legacyBundleSuffixes.contains {
                    segment.bundleIdentifier.hasSuffix($0)
                }
            }
            return segment.bundleIdentifier == ruleBundleIdentifier
        }

        var affectedDays: Set<UsageDayKey> = []
        var changedCount = 0
        for segment in matchingSegments
            where !segment.isUserModified && segment.category != category {
            affectedDays.formUnion(usageDayKeys(for: segment))
            segment.category = category
            changedCount += 1
        }

        for key in affectedDays {
            try rebuildDailyRecords(for: key, modelContext: modelContext)
        }

        try modelContext.save()
        if changedCount > 0 {
            postUsageChange()
        }
        return changedCount
    }

    static func exclude(
        bundleIdentifier: String,
        appName: String,
        modelContext: ModelContext
    ) throws {
        try prepareExclusion(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            modelContext: modelContext
        )
        try modelContext.save()
        CategoryManager.shared.setExcluded(bundleIdentifier: bundleIdentifier)
        postUsageChange()
    }

    private static func prepareClassification(
        bundleIdentifier: String,
        appName: String,
        category: String,
        modelContext: ModelContext
    ) throws {
        let rule = try upsertRule(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: category,
            isExcluded: false,
            modelContext: modelContext
        )
        rule.category = category
        rule.isExcluded = false

        let unclassifiedCategory = Constants.unclassifiedAppCategory
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.category == unclassifiedCategory
            }
        )
        for segment in try modelContext.fetch(segmentDescriptor) {
            segment.category = category
        }

        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.category == unclassifiedCategory
            }
        )
        for record in try modelContext.fetch(recordDescriptor) {
            record.category = category
        }
    }

    private static func prepareExclusion(
        bundleIdentifier: String,
        appName: String,
        modelContext: ModelContext
    ) throws {
        _ = try upsertRule(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: Constants.unclassifiedAppCategory,
            isExcluded: true,
            modelContext: modelContext
        )
    }

    private static func upsertRule(
        bundleIdentifier: String,
        appName: String,
        category: String,
        isExcluded: Bool,
        modelContext: ModelContext
    ) throws -> AppCategoryRule {
        var descriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.bundleIdentifier == bundleIdentifier }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.appName = appName
            existing.category = category
            existing.isUserDefined = true
            existing.isExcluded = isExcluded
            return existing
        }

        let rule = AppCategoryRule(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: category,
            isUserDefined: true,
            isExcluded: isExcluded
        )
        modelContext.insert(rule)
        return rule
    }

    private static func excludedBundleIdentifiers(
        modelContext: ModelContext
    ) -> Set<String> {
        let descriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.isExcluded == true }
        )
        return Set(
            ((try? modelContext.fetch(descriptor)) ?? []).map(\.bundleIdentifier)
        )
    }

    private static func usageDayKeys(for segment: AppUsageSegment) -> Set<UsageDayKey> {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: segment.startTime)
        var keys: Set<UsageDayKey> = []

        while day < segment.endTime {
            keys.insert(UsageDayKey(
                bundleIdentifier: segment.bundleIdentifier,
                date: day
            ))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }
        return keys
    }

    private static func rebuildDailyRecords(
        for key: UsageDayKey,
        modelContext: ModelContext
    ) throws {
        let calendar = Calendar.current
        let dayStart = key.date
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return
        }

        let bundleIdentifier = key.bundleIdentifier
        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier && $0.date == dayStart
            }
        )
        for record in try modelContext.fetch(recordDescriptor) {
            modelContext.delete(record)
        }

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.startTime < dayEnd
                    && $0.endTime > dayStart
            }
        )
        var totals: [String: DailyCategoryTotal] = [:]
        for segment in try modelContext.fetch(segmentDescriptor) {
            let clippedStart = max(dayStart, segment.startTime)
            let clippedEnd = min(dayEnd, segment.endTime)
            let durationSeconds = max(
                0,
                Int(clippedEnd.timeIntervalSince(clippedStart))
            )
            guard durationSeconds > 0 else { continue }

            if var existing = totals[segment.category] {
                existing.durationSeconds += durationSeconds
                if segment.endTime > existing.latestEndTime {
                    existing.appName = segment.appName
                    existing.latestEndTime = segment.endTime
                }
                totals[segment.category] = existing
            } else {
                totals[segment.category] = DailyCategoryTotal(
                    appName: segment.appName,
                    durationSeconds: durationSeconds,
                    latestEndTime: segment.endTime
                )
            }
        }

        for (category, total) in totals {
            let record = AppUsageRecord(
                appName: total.appName,
                bundleIdentifier: bundleIdentifier,
                category: category,
                date: dayStart
            )
            record.durationSeconds = total.durationSeconds
            modelContext.insert(record)
        }
    }

    private static func postUsageChange() {
        NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
    }
}
