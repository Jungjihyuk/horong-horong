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
