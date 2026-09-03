import Foundation
import SwiftData

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
