import Foundation
import SwiftData

@Model
final class AppCategoryRule {
    var id: UUID
    var bundleIdentifier: String
    var appName: String
    var category: String
    var isUserDefined: Bool
    var isExcluded: Bool = false

    init(
        bundleIdentifier: String,
        appName: String,
        category: String,
        isUserDefined: Bool = false,
        isExcluded: Bool = false
    ) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.category = category
        self.isUserDefined = isUserDefined
        self.isExcluded = isExcluded
    }
}

struct WebsiteCategoryMatch: Equatable {
    let domain: String
    let category: String
}

enum WebsiteCategoryRule {
    static let bundleIdentifierPrefix = "website-domain://"

    static func normalizedDomain(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let source = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: source),
              var host = components.host?.lowercased(),
              !host.isEmpty,
              !host.contains(where: \.isWhitespace) else {
            return nil
        }

        while host.hasSuffix(".") {
            host.removeLast()
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        guard !host.isEmpty else { return nil }
        return host
    }

    static func bundleIdentifier(for domain: String) -> String {
        "\(bundleIdentifierPrefix)\(domain)"
    }

    static func domain(from bundleIdentifier: String) -> String? {
        guard bundleIdentifier.hasPrefix(bundleIdentifierPrefix) else { return nil }
        let domain = String(bundleIdentifier.dropFirst(bundleIdentifierPrefix.count))
        return normalizedDomain(from: domain)
    }

    static func bestMatch(
        for url: String,
        rules: [String: String]
    ) -> WebsiteCategoryMatch? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased() else {
            return nil
        }

        return rules.keys
            .filter { host == $0 || host.hasSuffix(".\($0)") }
            .sorted { $0.count > $1.count }
            .first
            .flatMap { domain in
                rules[domain].map {
                    WebsiteCategoryMatch(domain: domain, category: $0)
                }
            }
    }
}

struct UnclassifiedAppUsage: Identifiable, Equatable {
    let bundleIdentifier: String
    let appName: String
    let durationSeconds: Int

    var id: String { bundleIdentifier }
}

struct ProductivityManagementAppUsage: Identifiable, Equatable {
    let bundleIdentifier: String
    let appName: String
    let durationSeconds: Int

    var id: String { bundleIdentifier }
}

enum UnclassifiedAppChoice: Equatable {
    case category(String)
    case excluded
}

@MainActor
enum DefaultAppCategoryRuleStore {
    static func reconcile(in modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<AppCategoryRule>()
        let existingRules = try modelContext.fetch(descriptor)
        let existingBundleIdentifiers = Set(existingRules.map(\.bundleIdentifier))

        for existing in existingRules where !existing.isUserDefined && !existing.isExcluded {
            guard let defaultRule = Constants.defaultCategoryRule(
                for: existing.bundleIdentifier,
                includingHidden: true
            ),
                  !Constants.isDefaultCategoryRuleHidden(existing.bundleIdentifier) else {
                modelContext.delete(existing)
                continue
            }

            existing.appName = defaultRule.appName
            existing.category = defaultRule.category
        }

        for rule in Constants.allDefaultCategoryRules
            where !existingBundleIdentifiers.contains(rule.bundleId)
                && !Constants.isDefaultCategoryRuleHidden(rule.bundleId) {
            modelContext.insert(AppCategoryRule(
                bundleIdentifier: rule.bundleId,
                appName: rule.appName,
                category: rule.category,
                isUserDefined: false
            ))
        }

        try modelContext.save()
    }
}

@MainActor
enum AppClassificationService {
    static func productivityManagementAppUsages(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [ProductivityManagementAppUsage] {
        guard end > start else { return [] }
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
                let clippedStart = max(start, segment.startTime)
                let clippedEnd = min(end, segment.endTime)
                return total + max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
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
                let clippedStart = max(start, segment.startTime)
                let clippedEnd = min(end, segment.endTime)
                return total + max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
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

    private static func postUsageChange() {
        NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
    }
}
