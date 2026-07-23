import Foundation
import SwiftData

final class CategoryManager: @unchecked Sendable {
    enum TrackingClassification: Equatable {
        case category(String)
        case unclassified
        case excluded
    }

    static let shared = CategoryManager()

    private var userRules: [String: String] = [:]
    private var websiteRules: [String: String] = [:]
    private var excludedBundleIdentifiers: Set<String> = []

    private init() {}

    func loadUserRules(from context: ModelContext) {
        migrateLegacyProductivityManagementCategory(in: context)
        userRules.removeAll()
        websiteRules.removeAll()
        excludedBundleIdentifiers.removeAll()

        for rule in Constants.defaultWebsiteCategoryRules {
            let bundleIdentifier = WebsiteCategoryRule.bundleIdentifier(for: rule.domain)
            guard !Constants.isDefaultCategoryRuleHidden(bundleIdentifier) else { continue }
            websiteRules[rule.domain] = rule.category
        }

        let descriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.isUserDefined == true }
        )
        if let rules = try? context.fetch(descriptor) {
            for rule in rules {
                if let domain = WebsiteCategoryRule.domain(from: rule.bundleIdentifier) {
                    websiteRules[domain] = rule.category
                    continue
                }
                if rule.isExcluded {
                    excludedBundleIdentifiers.insert(rule.bundleIdentifier)
                } else {
                    userRules[rule.bundleIdentifier] = rule.category
                }
            }
        }
    }

    func category(for bundleIdentifier: String) -> String {
        guard WebsiteCategoryRule.domain(from: bundleIdentifier) == nil else {
            return Constants.categoryName("기타")
        }
        if let userCategory = userRules[bundleIdentifier] {
            return userCategory
        }
        return Constants.defaultCategoryRule(for: bundleIdentifier)?.category ?? Constants.categoryName("기타")
    }

    /// 매핑된 카테고리만 반환. 매핑이 없으면 nil (추적 대상이 아님).
    /// 브라우저처럼 URL 기반으로 별도 분류하는 경우는 이 메서드를 통해서는 nil 이 나오도록
    /// defaultRules 에도 넣지 않아야 한다.
    func matchedCategory(for bundleIdentifier: String) -> String? {
        guard WebsiteCategoryRule.domain(from: bundleIdentifier) == nil else {
            return nil
        }
        if let userCategory = userRules[bundleIdentifier] {
            return userCategory
        }
        return Constants.defaultCategoryRule(for: bundleIdentifier)?.category
    }

    func trackingClassification(for bundleIdentifier: String) -> TrackingClassification {
        if excludedBundleIdentifiers.contains(bundleIdentifier) {
            return .excluded
        }
        if let category = matchedCategory(for: bundleIdentifier) {
            return .category(category)
        }
        return .unclassified
    }

    func websiteMatch(for url: String) -> WebsiteCategoryMatch? {
        WebsiteCategoryRule.bestMatch(for: url, rules: websiteRules)
    }

    var hasWebsiteRules: Bool {
        !websiteRules.isEmpty
    }

    func setUserRule(bundleIdentifier: String, category: String) {
        if let domain = WebsiteCategoryRule.domain(from: bundleIdentifier) {
            websiteRules[domain] = category
            return
        }
        excludedBundleIdentifiers.remove(bundleIdentifier)
        userRules[bundleIdentifier] = category
    }

    func removeUserRule(bundleIdentifier: String) {
        if let domain = WebsiteCategoryRule.domain(from: bundleIdentifier) {
            websiteRules.removeValue(forKey: domain)
            return
        }
        userRules.removeValue(forKey: bundleIdentifier)
        excludedBundleIdentifiers.remove(bundleIdentifier)
    }

    func setExcluded(bundleIdentifier: String) {
        userRules.removeValue(forKey: bundleIdentifier)
        excludedBundleIdentifiers.insert(bundleIdentifier)
    }

    func colorForCategory(_ category: String) -> String {
        Constants.categoryEmoji(for: category)
    }

    private func migrateLegacyProductivityManagementCategory(
        in context: ModelContext
    ) {
        let legacyCategory = Constants.legacySupportAppCategory
        let currentCategory = Constants.productivityManagementAppCategory
        var changed = false

        let ruleDescriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.category == legacyCategory }
        )
        for rule in (try? context.fetch(ruleDescriptor)) ?? [] {
            rule.category = currentCategory
            changed = true
        }

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.category == legacyCategory }
        )
        for segment in (try? context.fetch(segmentDescriptor)) ?? [] {
            segment.category = currentCategory
            changed = true
        }

        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.category == legacyCategory }
        )
        for record in (try? context.fetch(recordDescriptor)) ?? [] {
            record.category = currentCategory
            changed = true
        }

        if changed {
            try? context.save()
        }
    }
}
