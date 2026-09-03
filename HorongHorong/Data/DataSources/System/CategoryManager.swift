import Foundation

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

    /// 저장된 규칙을 메모리로 올린다. **분류는 이 사본으로만 한다** —
    /// 앱을 옮길 때마다 DB 를 읽으면 5초 폴링이 그대로 조회가 된다.
    @MainActor
    func loadUserRules(from repository: AppUsageRepository) {
        repository.migrateLegacyProductivityManagementCategory()
        userRules.removeAll()
        websiteRules.removeAll()
        excludedBundleIdentifiers.removeAll()

        for rule in Constants.defaultWebsiteCategoryRules {
            let bundleIdentifier = WebsiteCategoryRule.bundleIdentifier(for: rule.domain)
            guard !Constants.isDefaultCategoryRuleHidden(bundleIdentifier) else { continue }
            setWebsiteCategory(rule.category, for: rule.domain)
        }

        do {
            let rules = repository.userDefinedRules()
            var persistedWebsiteRules: [(domain: String, category: String)] = []
            for rule in rules {
                if let domain = WebsiteCategoryRule.domain(from: rule.bundleIdentifier) {
                    persistedWebsiteRules.append((domain, rule.category))
                    continue
                }
                if rule.isExcluded {
                    excludedBundleIdentifiers.insert(rule.bundleIdentifier)
                } else {
                    userRules[rule.bundleIdentifier] = rule.category
                }
            }

            for rule in persistedWebsiteRules where
                !Constants.websiteAliases(for: rule.domain).isEmpty {
                setWebsiteCategory(rule.category, for: rule.domain)
            }
            for rule in persistedWebsiteRules where
                Constants.websiteAliases(for: rule.domain).isEmpty {
                websiteRules[rule.domain] = rule.category
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
            setWebsiteCategory(category, for: domain)
            return
        }
        excludedBundleIdentifiers.remove(bundleIdentifier)
        userRules[bundleIdentifier] = category
    }

    func removeUserRule(bundleIdentifier: String) {
        if let domain = WebsiteCategoryRule.domain(from: bundleIdentifier) {
            for relatedDomain in Constants.websiteRuleDomains(for: domain) {
                websiteRules.removeValue(forKey: relatedDomain)
            }
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

    private func setWebsiteCategory(_ category: String, for domain: String) {
        for relatedDomain in Constants.websiteRuleDomains(for: domain) {
            websiteRules[relatedDomain] = category
        }
    }

}
