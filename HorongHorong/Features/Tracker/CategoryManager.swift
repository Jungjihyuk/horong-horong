import Foundation
import SwiftData

final class CategoryManager: @unchecked Sendable {
    static let shared = CategoryManager()

    private var userRules: [String: String] = [:]

    private init() {}

    func loadUserRules(from context: ModelContext) {
        userRules.removeAll()
        let descriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.isUserDefined == true }
        )
        if let rules = try? context.fetch(descriptor) {
            for rule in rules {
                userRules[rule.bundleIdentifier] = rule.category
            }
        }
    }

    func category(for bundleIdentifier: String) -> String {
        if let userCategory = userRules[bundleIdentifier] {
            return userCategory
        }
        return Constants.defaultCategoryRule(for: bundleIdentifier)?.category ?? Constants.categoryName("기타")
    }

    /// 매핑된 카테고리만 반환. 매핑이 없으면 nil (추적 대상이 아님).
    /// 브라우저처럼 URL 기반으로 별도 분류하는 경우는 이 메서드를 통해서는 nil 이 나오도록
    /// defaultRules 에도 넣지 않아야 한다.
    func matchedCategory(for bundleIdentifier: String) -> String? {
        if let userCategory = userRules[bundleIdentifier] {
            return userCategory
        }
        return Constants.defaultCategoryRule(for: bundleIdentifier)?.category
    }

    func setUserRule(bundleIdentifier: String, category: String) {
        userRules[bundleIdentifier] = category
    }

    func removeUserRule(bundleIdentifier: String) {
        userRules.removeValue(forKey: bundleIdentifier)
    }

    func colorForCategory(_ category: String) -> String {
        Constants.categoryEmoji(for: category)
    }
}
