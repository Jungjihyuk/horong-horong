import Foundation
import SwiftData

@Model
final class AppUsageRecord {
    var id: UUID
    var appName: String
    var bundleIdentifier: String
    var category: String
    var date: Date
    var durationSeconds: Int

    init(appName: String, bundleIdentifier: String, category: String, date: Date) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.date = Calendar.current.startOfDay(for: date)
        self.durationSeconds = 0
    }
}
